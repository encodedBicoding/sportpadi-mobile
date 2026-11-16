import 'dart:async';
import 'dart:io';
import 'dart:math' show Random, max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Getting a highlight's files ready ON THE PHONE, before anything is
/// uploaded (workspace `docs/wiki/highlights.md`, "things a client must
/// know"):
///
///  * a video is compressed to 720p H.264 MP4 (the server takes at most
///    40 MB from the app and does not convert app uploads), and one frame is
///    saved as its poster;
///  * every photo and poster is decoded to pixels and written out as a NEW
///    JPEG, so no EXIF — and so no GPS position — can survive;
///  * the compressed MP4's own metadata boxes are blanked too: the phone's
///    encoder may copy the recording's location across.
///
/// The server serves photos and posters exactly as uploaded and only CHECKS
/// an app video (a position left in the file gets the post taken down), so
/// this is the place where "where it was taken" is stripped.

/// The app's caps — the same numbers the server checks
/// (`packages/lib/src/highlights.ts`).
class HighlightLimits {
  static const videoMaxSeconds = 60;

  /// How far past the limit a clip may run. The server allows a second
  /// (encoders round a 60.0 s clip differently, and a phone's camera stops a
  /// moment after its own limit); the phone stays just inside that — for the
  /// picked file before it is compressed, and for the compressed file (the
  /// one the server measures; it can come out a few hundredths longer)
  /// before it is uploaded. A clip that passes here is then not refused
  /// there, after a 40 MB upload.
  static const videoSourceSlackMs = 800;
  static const videoOutputSlackMs = 900;
  static const appVideoMaxBytes = 40 * 1024 * 1024;
  static const imageMaxBytes = 10 * 1024 * 1024;
  static const maxPhotos = 10;
  static const captionMax = 300;
  static const commentMax = 500;
  static const reportNoteMax = 500;

  /// Long edge of an uploaded photo, in pixels.
  static const photoLongEdge = 1440;

  /// A 720p video's long edge — the poster never needs more.
  static const posterLongEdge = 1280;
}

/// A problem preparing a file, with a message fit to show as it is.
class HighlightMediaException implements Exception {
  HighlightMediaException(this.message, {this.unexplained = false});
  final String message;

  /// True when the phone simply couldn't do it and nothing says why (the
  /// encoder gave no file, the result couldn't be read, the read of the
  /// clip's length never answered) — as opposed to a clip that is too long
  /// or too large. The composer words such a failure differently when the
  /// app was in the background meanwhile: iOS stops the export of an app
  /// that isn't on screen, whatever the video.
  final bool unexplained;
  @override
  String toString() => message;
}

/// Thrown when the person cancelled the compression themselves.
class HighlightMediaCancelled implements Exception {
  const HighlightMediaCancelled();
}

class PreparedImage {
  const PreparedImage({
    required this.file,
    required this.width,
    required this.height,
    required this.bytes,
  });
  final File file;
  final int width;
  final int height;
  final int bytes;
}

class PreparedVideo {
  const PreparedVideo({
    required this.file,
    required this.bytes,
    required this.poster,
    required this.width,
    required this.height,
    this.durationMs,
  });
  final File file;
  final int bytes;

  /// A frame of the video, upright. On Android the plugin makes it at most
  /// 512 px on its long edge, so its size is NOT the video's.
  final PreparedImage poster;

  /// The video's size as it is shown (after rotation) — what the server is
  /// told.
  final int width;
  final int height;
  final int? durationMs;
}

/// A post's `clientId`: minted once per post, reused on every retry
/// (8–64 of `A-Za-z0-9_-`).
String newHighlightClientId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  final sb = StringBuffer('app-');
  for (var i = 0; i < 28; i++) {
    sb.write(chars[r.nextInt(chars.length)]);
  }
  return sb.toString();
}

int _fileSeq = 0;

/// Our own scratch folder inside the app's temp directory.
Future<Directory> _workDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/highlights');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<File> _newFile(String ext) async {
  final dir = await _workDir();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return File('${dir.path}/hl_${stamp}_${_fileSeq++}.$ext');
}

/// Throw away everything this module wrote. Best-effort.
Future<void> clearHighlightScratch() async {
  try {
    final dir = await _workDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {/* nothing depends on it */}
  await _clearPluginCache();
}

/// The compressor's own folder (what it wrote, finished or not). Left alone
/// while it is working.
Future<void> _clearPluginCache() async {
  try {
    if (!_videoBusy && !VideoCompress.isCompressing) {
      await VideoCompress.deleteAllCache();
    }
  } catch (_) {/* nothing depends on it */}
}

/// Delete files this module made. Best-effort.
Future<void> _discard(List<File> files, {bool pluginCache = false}) async {
  for (final f in files) {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {/* nothing depends on it */}
  }
  if (pluginCache) await _clearPluginCache();
}

int _composers = 0;

/// A composer opened: its prepared files live in the scratch folder until
/// [highlightComposerClosed].
void highlightComposerOpened() => _composers++;

/// A composer closed (its post was published, or it was abandoned). The
/// scratch folder is emptied once NO composer is open — a second one, opened
/// by a link while the first is still up, must not lose its files to the
/// first one's goodbye.
Future<void> highlightComposerClosed() async {
  if (_composers > 0) _composers--;
  if (_composers == 0) await clearHighlightScratch();
}

// ── photos ──────────────────────────────────────────────────────────────────

class _JpegJob {
  const _JpegJob(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// JPEG quality of every photo and poster.
const _jpegQuality = 86;

/// Runs in a background isolate: the JPEG encoder is pure Dart and would
/// freeze the screen for the better part of a second per photo.
Uint8List _encodeJpeg(_JpegJob job) {
  var rgba = job.rgba;
  // The pixels arrive premultiplied, and a JPEG has no transparency: a
  // see-through area (a PNG cut-out, a sticker) would come out black. Lay
  // such a picture on white instead.
  var opaque = true;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 255) {
      opaque = false;
      break;
    }
  }
  if (!opaque) {
    final flat = Uint8List.fromList(rgba);
    for (var i = 0; i + 3 < flat.length; i += 4) {
      final rest = 255 - flat[i + 3];
      if (rest == 0) continue;
      for (var c = 0; c < 3; c++) {
        final v = flat[i + c] + rest;
        flat[i + c] = v > 255 ? 255 : v;
      }
      flat[i + 3] = 255;
    }
    rgba = flat;
  }
  // Built from bare pixels: there is no metadata to carry over.
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: _jpegQuality);
}

/// Decode [encoded] (any format the phone can draw — JPEG, PNG, HEIC, WebP),
/// shrink it so its long edge is at most [longEdge], and write a fresh JPEG.
Future<PreparedImage> _reencodeAsJpeg(Uint8List encoded,
    {required int longEdge}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    if (w <= 0 || h <= 0) {
      throw HighlightMediaException(l10n.highlights_photoUnreadable);
    }
    // Only ONE target size is given, so the engine keeps the proportions
    // itself — whichever way round it reports a rotated photo.
    if (w >= h) {
      codec = await descriptor.instantiateCodec(
          targetWidth: w > longEdge ? longEdge : w);
    } else {
      codec = await descriptor.instantiateCodec(
          targetHeight: h > longEdge ? longEdge : h);
    }
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw HighlightMediaException(l10n.highlights_photoUnreadable);
    }
    final rgba =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final width = image.width;
    final height = image.height;
    final jpeg = await compute(_encodeJpeg, _JpegJob(rgba, width, height));
    if (jpeg.length > HighlightLimits.imageMaxBytes) {
      throw HighlightMediaException(l10n.highlights_appPhotoTooLarge);
    }
    final out = await _newFile('jpg');
    await out.writeAsBytes(jpeg, flush: true);
    return PreparedImage(
        file: out, width: width, height: height, bytes: jpeg.length);
  } on HighlightMediaException {
    rethrow;
  } catch (_) {
    throw HighlightMediaException(l10n.highlights_photoUnreadable);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// One picked photo → a downscaled JPEG with no EXIF.
Future<PreparedImage> prepareHighlightPhoto(String sourcePath) async {
  final Uint8List bytes;
  try {
    bytes = await File(sourcePath).readAsBytes();
  } catch (_) {
    throw HighlightMediaException(l10n.highlights_photoUnreadable);
  }
  return _reencodeAsJpeg(bytes, longEdge: HighlightLimits.photoLongEdge);
}

// ── video ───────────────────────────────────────────────────────────────────

/// How long the video at [path] is: `ms` in milliseconds, null when the
/// phone can't tell — and `timedOut`, true when the read gave up rather
/// than answering at all.
///
/// Bounded, like the thumbnail's call: the plugin reads the file on the
/// platform thread (`AVURLAsset` on iOS, `MediaMetadataRetriever` on
/// Android) and a file it cannot get to the end of — one iCloud has
/// evicted, one a stopped download left half written — answers neither a
/// length nor an error. Both callers sit inside [prepareHighlightVideo]'s
/// [_videoBusy] window, so waiting for ever would hold the composer for the
/// life of the process: exactly what the export's own watchdog is there to
/// prevent. A read this slow counts as "the phone can't tell", which every
/// caller already handles.
///
/// Giving up and answering nothing are not the same thing, and a length
/// alone cannot tell them apart. A file in which iOS finds no video track
/// is ANSWERED, and at once — with an empty description (the plugin, 3.1.4,
/// sends back `{}`), so no length is in it and this leaves through the
/// `d == null` line below with `timedOut: false`; only a timeout means the
/// channel itself went quiet. On iOS [prepareHighlightVideo] refuses a file
/// of the first kind before it compresses anything, so the compression's
/// stall watchdog — the one place that can see a wedged encoder — is never
/// reached on that path, and the difference has to be carried out of here.
///
/// It records no wedge ([_encoderWedged]): `getMediaInfo` never touches the
/// plugin's `isCompressing` (3.1.4 sets that only around `compressVideo`),
/// so there is no stuck flag to read one off. Nor is it remembered in a
/// field of our own: that would still be true for the NEXT clip, which may
/// be a file this phone reads perfectly well. It belongs to this one read,
/// so it is returned with it.
Future<({int? ms, bool timedOut})> highlightVideoDuration(String path) async {
  try {
    final info = await VideoCompress.getMediaInfo(path)
        .timeout(const Duration(seconds: 15));
    final d = info.duration;
    if (d == null || d <= 0) return (ms: null, timedOut: false);
    return (ms: d.round(), timedOut: false);
  } on TimeoutException {
    return (ms: null, timedOut: true);
  } catch (_) {
    return (ms: null, timedOut: false);
  }
}

/// A video is being prepared — from the first look at the file to its
/// poster, not only while the encoder runs. One at a time: the plugin has a
/// single export and a single progress stream.
bool _videoBusy = false;

/// The person asked to stop. The plugin can't be trusted to say so itself:
/// on Android a compression that FAILED answers exactly like a cancelled
/// one, and on iOS a cancel sent while nothing is exporting is remembered
/// and makes the next export report "cancelled".
bool _cancelRequested = false;

/// The phone's encoder stopped answering and the plugin still believes an
/// export is running. `VideoCompress.isCompressing` is a plain Dart flag
/// (3.1.4 `CompressMixin`): `compressVideo` sets it before the native call
/// and clears it only when that call RETURNS, and `cancelCompression()`
/// does not touch it. A hung export therefore leaves it true for the life
/// of the process, and the plugin then refuses every later export. Our own
/// flag so the next video is told the truth ("reopen SportPadi") instead of
/// "another video is still being prepared", which would never come true.
bool _encoderWedged = false;

/// Is the encoder still wedged? The plugin letting go after all — its
/// export answered long after the watchdog gave up on it — is the one way
/// out short of restarting the app.
bool _encoderStuck() {
  if (_encoderWedged && !VideoCompress.isCompressing) _encoderWedged = false;
  return _encoderWedged;
}

/// Stop the video being prepared: [prepareHighlightVideo] then throws
/// [HighlightMediaCancelled] — at once while the encoder runs, otherwise at
/// its next step. Does nothing when no video is being prepared.
Future<void> cancelHighlightVideo() async {
  if (!_videoBusy) return;
  _cancelRequested = true;
  // Only while an export is really running (see [_cancelRequested]).
  if (!VideoCompress.isCompressing) return;
  try {
    await VideoCompress.cancelCompression();
  } catch (_) {/* nothing was running after all */}
}

/// "That video couldn't be prepared on this phone" — no reason known.
HighlightMediaException _videoFailed() =>
    HighlightMediaException(l10n.highlights_videoFailed, unexplained: true);

/// What to throw after a pass that ended badly. The plugin clears its "a
/// compression is running" only when `compressVideo` returns: if it still
/// says one is running, this process can prepare no further video
/// ([_encoderWedged]) and the person is told that instead of being sent to
/// try another clip. Not [HighlightMediaException.unexplained]: being in
/// the background is not what this was.
HighlightMediaException _afterFailedPass() {
  if (VideoCompress.isCompressing) _encoderWedged = true;
  return _encoderWedged
      ? HighlightMediaException(l10n.highlights_appEncoderStuck)
      : _videoFailed();
}

/// No progress event for this long while an export runs = the phone's
/// encoder has stopped answering. The plugin reports every few per cent, so
/// a working export is never this quiet; iOS stops an export outright when
/// the app leaves the screen, and then says nothing at all.
const _encoderStall = Duration(seconds: 45);

/// A single pass can't take longer than this, whatever it reports. A clip is
/// at most 61 s and is encoded at 720p or below, so minutes are plenty —
/// this is only here so a hung export can't hold the composer for the life
/// of the process.
const _encoderLimit = Duration(minutes: 5);

/// Wait for one export, but not for ever: a native exporter that answers
/// neither "done" nor "failed" would otherwise hold [_videoBusy] — and the
/// composer with it — for the life of the process (the plugin's own flag
/// stays stuck whatever we do: [_encoderWedged]).
///
/// Gives up when [_encoderStall] passes with no progress event (only once
/// this phone has shown it reports progress at all — were it silent
/// throughout, every export would be given up on) or when the pass has run
/// for [_encoderLimit]. [lastProgressAt] is when the current run's progress
/// was last seen, null while none has been.
Future<MediaInfo?> _boundedExport(
  Future<MediaInfo?> export, {
  required DateTime? Function() lastProgressAt,
}) {
  final out = Completer<MediaInfo?>();
  final started = DateTime.now();
  late final Timer watch;
  void settle(void Function() how) {
    watch.cancel();
    if (!out.isCompleted) how();
  }

  watch = Timer.periodic(const Duration(seconds: 5), (_) {
    final now = DateTime.now();
    final tick = lastProgressAt();
    final quiet = tick != null && tick.isAfter(started)
        ? now.difference(tick)
        : now.difference(started);
    if ((tick != null && quiet >= _encoderStall) ||
        now.difference(started) >= _encoderLimit) {
      settle(() => out.completeError(
          TimeoutException('video export', now.difference(started))));
    }
  });
  // The export may still finish afterwards; its answer is then dropped (and
  // its error handled here, so it can't surface as an unhandled one).
  export.then<void>((info) => settle(() => out.complete(info)),
      onError: (Object e, StackTrace st) =>
          settle(() => out.completeError(e, st)));
  return out.future;
}

/// One run of the phone's encoder at [quality]. Throws
/// [HighlightMediaCancelled] when the person stopped it, and a
/// [HighlightMediaException] when it produced nothing — a hung export
/// included ([_boundedExport]).
Future<MediaInfo> _compressPass(String sourcePath, VideoQuality quality,
    void Function(double fraction)? onProgress,
    {required DateTime? Function() lastProgressAt}) async {
  // iOS: a cancel that reaches the plugin just after an export ended is
  // remembered, and the NEXT export then says "cancelled" although it ran to
  // the end. Nobody cancelled this one, so it is run again — once.
  for (var attempt = 0; attempt < 2; attempt++) {
    onProgress?.call(0.0);
    final MediaInfo? info;
    try {
      info = await _boundedExport(
        VideoCompress.compressVideo(
          sourcePath,
          quality: quality,
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 30,
        ),
        lastProgressAt: lastProgressAt,
      );
    } on TimeoutException {
      // The encoder stopped answering. Ask the plugin to let go of the
      // native export — only while it says one is running, as a cancel
      // sent at any other moment is remembered by iOS (see
      // [_cancelRequested]). This does NOT clear the plugin's own "I am
      // compressing"; [_afterFailedPass] takes care of that.
      if (VideoCompress.isCompressing) {
        try {
          // Bounded like the thumbnail's: this channel is the one that has
          // just stopped answering, and waiting on it for ever would hold
          // the composer exactly as the hung export would.
          await VideoCompress.cancelCompression()
              .timeout(const Duration(seconds: 5));
        } catch (_) {/* it had stopped after all, or said nothing */}
      }
      if (_cancelRequested) throw const HighlightMediaCancelled();
      throw _afterFailedPass();
    } catch (_) {
      // iOS answers a failed export without a file path, which the plugin's
      // own parsing throws on. A throw from the channel itself (no plugin
      // on the other side, a codec error) skips the line that clears the
      // plugin's flag, so this ends the same way.
      if (_cancelRequested) throw const HighlightMediaCancelled();
      throw _afterFailedPass();
    }
    if (_cancelRequested) throw const HighlightMediaCancelled();
    // Android answers null for a FAILED compression exactly as for a
    // cancelled one. We didn't cancel, so it failed — and the person is told
    // (they used to be sent back to the start without a word).
    if (info == null) {
      throw _videoFailed();
    }
    if (info.isCancel != true) return info;
  }
  throw _videoFailed();
}

/// Compress the picked video for upload and make its poster.
///
/// 720p first. Should the phone's encoder come out over the server's 40 MB
/// (an iPhone's 720p preset is generous with bitrate), it is done again
/// one size down rather than refusing a clip the person is allowed to post.
/// [onProgress] gets 0–1 for the pass that is running.
///
/// Never pass the plugin's `duration:` to trim a long clip: on Android that
/// number is cut off the END (on iOS it is the length to keep).
Future<PreparedVideo> prepareHighlightVideo(
  String sourcePath, {
  void Function(double fraction)? onProgress,
}) async {
  if (_videoBusy || _encoderStuck()) {
    throw HighlightMediaException(_videoBusy
        ? l10n.highlights_videoBusy
        : l10n.highlights_appEncoderStuck);
  }
  _videoBusy = true;
  _cancelRequested = false;

  void stopIfCancelled() {
    if (_cancelRequested) throw const HighlightMediaCancelled();
  }

  // Everything this run writes. What isn't handed back is deleted — also
  // when the composer was closed meanwhile and has already emptied the
  // scratch folder (these are written after that).
  final made = <File>[];
  Subscription? progress;
  var finished = false;
  try {
    final tooLong =
        l10n.highlights_appVideoTooLong(HighlightLimits.videoMaxSeconds);
    const maxMs = HighlightLimits.videoMaxSeconds * 1000;
    final source = await highlightVideoDuration(sourcePath);
    final sourceMs = source.ms;
    stopIfCancelled();
    // iOS: the plugin can say nothing about a file in which it finds no
    // video track — and its exporter then takes the whole app down with it.
    // Such a file is refused here, before the export that would crash.
    //
    // A read that gave up is a different thing: it is the channel that went
    // quiet, not the file that was unreadable. This refusal comes BEFORE
    // the compression, so on iOS the stall watchdog never gets to say so —
    // and the person would be sent from clip to clip, fifteen seconds each,
    // never told that reopening the app is what helps. So say it here.
    // Not [_afterFailedPass]: nothing is exporting, so the plugin's own
    // flag has nothing to tell. Nothing is marked wedged either — the next
    // clip is still worth a try, and this one gets no faster by refusing it.
    //
    // It IS [HighlightMediaException.unexplained], though, like the
    // refusal it replaced: nothing says why the read never answered, and
    // when the app was in the background while it waited, that is the
    // likelier reason. The composer then says "keep the app open" and
    // offers Try again, as it did before this had a sentence of its own —
    // "close the app completely" is for the read that went quiet with the
    // app on screen, and that case reads exactly as before.
    if (Platform.isIOS && sourceMs == null) {
      throw source.timedOut
          ? HighlightMediaException(l10n.highlights_appEncoderStuck,
              unexplained: true)
          : _videoFailed();
    }
    if (sourceMs != null &&
        sourceMs > maxMs + HighlightLimits.videoSourceSlackMs) {
      throw HighlightMediaException(tooLong);
    }

    // Android: the plugin hands the path to the encoder as a URI, so a '#',
    // '?', '%' or ':' in it ("Goal #2.mp4" — the picker keeps the gallery's
    // name for its copy) points at a file that isn't there, and that video
    // could never be prepared. It is compressed from a copy under a plain
    // name instead.
    var input = sourcePath;
    if (Platform.isAndroid && sourcePath.contains(RegExp(r'[#?%:]'))) {
      final copy = await File(sourcePath).copy((await _newFile('mp4')).path);
      made.add(copy);
      input = copy.path;
      stopIfCancelled();
    }

    // The plugin keeps a progress event that arrived after its last
    // listener left and hands it to the next one: nothing counts until this
    // run's encoder has started.
    var live = false;
    // When a progress event last arrived: the only sign a native export is
    // still working (the watchdog in [_boundedExport]).
    DateTime? lastTick;
    progress = VideoCompress.compressProgress$.subscribe((percent) {
      if (!live) return;
      lastTick = DateTime.now();
      final f = percent / 100.0;
      onProgress?.call(f < 0.0 ? 0.0 : (f > 1.0 ? 1.0 : f));
    });
    await Future<void>.delayed(Duration.zero);
    stopIfCancelled();
    live = true;

    const ladder = [
      VideoQuality.Res1280x720Quality,
      VideoQuality.Res960x540Quality,
      VideoQuality.Res640x480Quality,
    ];
    File? compressed;
    MediaInfo? encoded;
    for (final quality in ladder) {
      final info = await _compressPass(input, quality, onProgress,
          lastProgressAt: () => lastTick);
      final path = info.path;
      final out = info.file ?? (path == null ? null : File(path));
      if (out == null || !await out.exists()) {
        throw _videoFailed();
      }
      // Never the picked file itself, whatever the plugin answers.
      if (out.path != sourcePath) made.add(out);
      stopIfCancelled();
      if (await out.length() <= HighlightLimits.appVideoMaxBytes) {
        compressed = out;
        encoded = info;
        break;
      }
    }
    if (compressed == null) {
      throw HighlightMediaException(l10n.highlights_appVideoTooLarge);
    }

    // The encoder may have copied the recording's GPS position into the new
    // file; blank every metadata box before it can leave the phone.
    File clean;
    try {
      clean = await scrubMp4Metadata(compressed);
      if (clean.path == compressed.path) {
        // Nothing to blank. Still take it out of the plugin's folder, which
        // is emptied whenever a run is abandoned.
        clean = await compressed.copy((await _newFile('mp4')).path);
      }
    } catch (_) {
      throw _videoFailed();
    }
    made.add(clean);
    stopIfCancelled();
    final bytes = await clean.length();

    // The length that counts is the compressed file's — the one the server
    // measures. Refused here, before 40 MB go up for nothing.
    final outMs = (await highlightVideoDuration(clean.path)).ms ?? sourceMs;
    stopIfCancelled();
    if (outMs != null && outMs > maxMs + HighlightLimits.videoOutputSlackMs) {
      throw HighlightMediaException(tooLong);
    }

    final Uint8List? frame;
    try {
      // iOS never answers when it can't make the frame: don't wait for ever.
      frame = await VideoCompress.getByteThumbnail(clean.path,
              quality: 90, position: -1)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw _videoFailed();
    }
    stopIfCancelled();
    if (frame == null || frame.isEmpty) {
      throw _videoFailed();
    }
    final PreparedImage poster;
    try {
      poster = await _reencodeAsJpeg(frame,
          longEdge: HighlightLimits.posterLongEdge);
    } on HighlightMediaException {
      // Its own words are about a photo; this was the video's frame.
      throw _videoFailed();
    }
    made.add(poster.file);
    stopIfCancelled();

    // The size the server is told. The poster has the right SHAPE (a frame,
    // already upright) but on Android it is at most 512 px. The plugin's
    // numbers for the compressed file are full size, but on Android they
    // come the wrong way round for an upright clip. So: the file's numbers,
    // laid the way the poster lies — when the two describe the same picture.
    var width = poster.width;
    var height = poster.height;
    final w = encoded?.width, h = encoded?.height;
    if (w != null && h != null && w > 0 && h > 0) {
      final upright = poster.height >= poster.width;
      final vw = upright ? min(w, h) : max(w, h);
      final vh = upright ? max(w, h) : min(w, h);
      final shape = poster.width / poster.height;
      if ((vw / vh - shape).abs() <= 0.03 * shape) {
        width = vw;
        height = vh;
      }
    }

    finished = true;
    // The encoder's own output (not yet scrubbed), and any pass that came
    // out too large, have served their purpose.
    unawaited(_discard([
      for (final f in made)
        if (f.path != clean.path && f.path != poster.file.path) f
    ]));
    return PreparedVideo(
      file: clean,
      bytes: bytes,
      poster: poster,
      width: width,
      height: height,
      durationMs: outMs,
    );
  } on HighlightMediaException {
    rethrow;
  } on HighlightMediaCancelled {
    rethrow;
  } catch (_) {
    // Nothing raw is ever shown ("Bad state: …").
    throw _videoFailed();
  } finally {
    progress?.unsubscribe();
    _videoBusy = false;
    if (!finished) unawaited(_discard(made, pluginCache: true));
  }
}

// ── MP4 metadata ────────────────────────────────────────────────────────────

class _Mp4Box {
  const _Mp4Box(this.offset, this.size, this.header, this.type);
  final int offset;
  final int size;
  final int header;
  final String type;
}

int _u32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

int _u64(Uint8List b, int at) => _u32(b, at) * 4294967296 + _u32(b, at + 4);

String _fourcc(Uint8List b, int at) => String.fromCharCodes(b, at, at + 4);

/// The boxes laid end to end in `buf[start..end)`. A malformed one throws —
/// or, with [lenient], ends the list there: the boxes in front of it are
/// still returned.
List<_Mp4Box> _childBoxes(Uint8List buf, int start, int end,
    {required bool lenient}) {
  final out = <_Mp4Box>[];
  var pos = start;
  while (pos < end) {
    if (end - pos < 8) {
      if (lenient) break;
      throw const FormatException('mp4: short box header');
    }
    var size = _u32(buf, pos);
    var header = 8;
    if (size == 1) {
      if (end - pos < 16) {
        if (lenient) break;
        throw const FormatException('mp4: short box header');
      }
      size = _u64(buf, pos + 8);
      header = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < header || pos + size > end) {
      if (lenient) break;
      throw const FormatException('mp4: bad box size');
    }
    out.add(_Mp4Box(pos, size, header, _fourcc(buf, pos + 4)));
    pos += size;
  }
  return out;
}

/// Where descriptive metadata lives: `udta` (©xyz = the GPS position, titles,
/// device names) and `meta` (Apple's keyed metadata, location included).
const _metadataBoxes = {'udta', 'meta'};

/// Top-level boxes that are metadata only (`uuid` carries XMP).
const _topLevelMetadataBoxes = {'udta', 'meta', 'uuid'};

/// Boxes that only hold other boxes, from a track down to its sample
/// tables: a metadata box may sit at any of these levels.
const _containerBoxes = {'trak', 'mdia', 'minf', 'stbl'};

/// Report every metadata box among the boxes in `buf[start..end)` and in
/// the containers below them: [found] gets its offset in [buf], its size
/// and its header length.
///
/// [depth] 0 is moov's own children, 1 a track's. Those two levels must
/// read as boxes — a file where they don't is refused (the caller's
/// [FormatException]). No encoder we know writes metadata further down, so
/// there an odd box only ends the search of that branch: a file that plays
/// is not refused for it — and whatever stood in front of the odd box is
/// still looked at (a `udta` there must not escape because of its
/// neighbour).
void _findMetadata(Uint8List buf, int start, int end, int depth,
    void Function(int offset, int size, int header) found) {
  final boxes = _childBoxes(buf, start, end, lenient: depth >= 2);
  for (final box in boxes) {
    if (_metadataBoxes.contains(box.type)) {
      found(box.offset, box.size, box.header);
    } else if (_containerBoxes.contains(box.type) && depth < 4) {
      _findMetadata(buf, box.offset + box.header, box.offset + box.size,
          depth + 1, found);
    }
  }
}

/// A moov bigger than this isn't a 60-second clip's.
const _maxMoovBytes = 64 * 1024 * 1024;

/// Blank every metadata box of the MP4 at [source] — at the top level, in
/// `moov`, and in each track down to its sample tables: the box becomes a
/// `free` box of the same size with its contents zeroed. Nothing moves, so the
/// sample offsets stay right and the picture and sound are untouched (the
/// rotation lives in the track header, not in these boxes).
///
/// Returns [source] itself when there was nothing to blank, else a cleaned
/// copy. Throws a [FormatException] for a file that doesn't read as an MP4 —
/// the caller must then NOT upload it.
Future<File> scrubMp4Metadata(File source) async {
  final length = await source.length();
  // [start, end) byte ranges to zero, and where to write "free".
  final zero = <List<int>>[];
  final renames = <int>[];

  void blank(int offset, int size, int header) {
    renames.add(offset + 4);
    if (size > header) zero.add([offset + header, offset + size]);
  }

  final input = await source.open();
  try {
    var pos = 0;
    var sawMoov = false;
    while (pos < length) {
      await input.setPosition(pos);
      final head = await input.read(16);
      if (head.length < 8) throw const FormatException('mp4: short box header');
      var size = _u32(head, 0);
      var header = 8;
      if (size == 1) {
        if (head.length < 16) {
          throw const FormatException('mp4: short box header');
        }
        size = _u64(head, 8);
        header = 16;
      } else if (size == 0) {
        size = length - pos;
      }
      if (size < header || pos + size > length) {
        throw const FormatException('mp4: bad box size');
      }
      final type = _fourcc(head, 4);
      if (_topLevelMetadataBoxes.contains(type)) {
        blank(pos, size, header);
      } else if (type == 'moov') {
        sawMoov = true;
        if (size > _maxMoovBytes) {
          throw const FormatException('mp4: moov too large');
        }
        await input.setPosition(pos);
        final moov = await input.read(size);
        if (moov.length != size) {
          throw const FormatException('mp4: short moov');
        }
        final moovAt = pos;
        _findMetadata(
            moov,
            header,
            size,
            0,
            (offset, boxSize, boxHeader) =>
                blank(moovAt + offset, boxSize, boxHeader));
      }
      pos += size;
    }
    if (!sawMoov) throw const FormatException('mp4: no moov');
    if (renames.isEmpty) return source;

    // Copy the file through, changing only those bytes.
    final outFile = await _newFile('mp4');
    final output = await outFile.open(mode: FileMode.write);
    try {
      const free = [0x66, 0x72, 0x65, 0x65]; // "free"
      await input.setPosition(0);
      var at = 0;
      while (at < length) {
        final chunk = await input.read(1 << 16);
        if (chunk.isEmpty) break;
        final end = at + chunk.length;
        for (final range in zero) {
          final lo = range[0] > at ? range[0] : at;
          final hi = range[1] < end ? range[1] : end;
          if (hi > lo) chunk.fillRange(lo - at, hi - at, 0);
        }
        for (final r in renames) {
          for (var k = 0; k < 4; k++) {
            final where = r + k;
            if (where >= at && where < end) chunk[where - at] = free[k];
          }
        }
        await output.writeFrom(chunk);
        at = end;
      }
      await output.flush();
      if (at != length) throw const FormatException('mp4: short copy');
    } finally {
      await output.close();
    }
    return outFile;
  } finally {
    await input.close();
  }
}
