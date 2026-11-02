import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// A document a sport's teams may be asked for (owner console → Team
/// documents) and what one team has on file for it.
class DocumentType {
  const DocumentType({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.youthOnly = false,
  });
  final String id;
  final String name;

  /// file | text | file_or_text
  final String kind;
  final String? description;
  final bool youthOnly;

  bool get wantsFile => kind != 'text';
  bool get wantsText => kind != 'file';

  factory DocumentType.fromJson(Map<String, dynamic> j) => DocumentType(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Document',
        kind: j['kind'] as String? ?? 'file',
        description: j['description'] as String?,
        youthOnly: j['youthOnly'] == true,
      );
}

class TeamDocument {
  const TeamDocument({this.fileUrl, this.fileName, this.textValue, this.note, this.updatedAt});
  final String? fileUrl;
  final String? fileName;
  final String? textValue;
  final String? note;
  final DateTime? updatedAt;

  static TeamDocument? fromJson(dynamic j) => j is Map
      ? TeamDocument(
          fileUrl: j['fileUrl'] as String?,
          fileName: j['fileName'] as String?,
          textValue: j['textValue'] as String?,
          note: j['note'] as String?,
          updatedAt: j['updatedAt'] is String ? DateTime.tryParse(j['updatedAt'] as String) : null,
        )
      : null;
}

/// One row of a team's documents list / a registration checklist.
class DocumentItem {
  const DocumentItem({required this.type, required this.document, required this.ok});
  final DocumentType type;
  final TeamDocument? document;
  final bool ok;

  /// `{type, document, ok}` (forTeam) or a flattened checklist row
  /// (`{id, name, kind, description, ok, document}`).
  factory DocumentItem.fromJson(Map<String, dynamic> j) => DocumentItem(
        type: j['type'] is Map
            ? DocumentType.fromJson(Map<String, dynamic>.from(j['type'] as Map))
            : DocumentType.fromJson(j),
        document: TeamDocument.fromJson(j['document']),
        ok: j['ok'] == true,
      );
}

class DocumentsRepository {
  DocumentsRepository(this._dio);
  final Dio _dio;

  Future<List<DocumentItem>> forTeam(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/documents');
      final list = res.data is Map ? (res.data['documents'] as List? ?? const []) : const [];
      return [for (final e in list) if (e is Map) DocumentItem.fromJson(Map<String, dynamic>.from(e))];
    } catch (e) {
      throw apiError(e, fallback: "Could not load the team's documents.");
    }
  }

  Future<List<DocumentType>> types(String? categoryId) async {
    try {
      final res = await _dio.get('/api/mobile/documents/types',
          queryParameters: {if (categoryId != null) 'categoryId': categoryId});
      final list = res.data is List ? res.data as List : const [];
      return [for (final e in list) if (e is Map) DocumentType.fromJson(Map<String, dynamic>.from(e))];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the document list.');
    }
  }

  /// Presign + upload a document image; returns its public URL.
  Future<String> upload(String teamId, List<int> bytes, String contentType) async {
    try {
      final pre = await _dio.post('/api/mobile/upload-url', data: {
        'assetType': 'teamDocument',
        'contentType': contentType,
        'scopeId': teamId,
      });
      final d = Map<String, dynamic>.from(pre.data as Map);
      final headers = d['headers'] is Map ? Map<String, dynamic>.from(d['headers'] as Map) : <String, dynamic>{};
      final res = await Dio().put<void>(
        d['uploadUrl'] as String,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {...headers, 'Content-Length': bytes.length}, contentType: contentType),
      );
      if ((res.statusCode ?? 500) >= 300) throw ApiException('Upload failed.', statusCode: res.statusCode);
      return d['publicUrl'] as String;
    } catch (e) {
      throw apiError(e, fallback: 'Upload failed.');
    }
  }

  Future<void> save(String teamId, String documentTypeId,
      {String? fileUrl, String? fileName, String? textValue, String? note}) async {
    try {
      await _dio.post('/api/mobile/teams/$teamId/documents', data: {
        'documentTypeId': documentTypeId,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'textValue': textValue,
        'note': note,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not save the document.');
    }
  }

  Future<void> remove(String teamId, String documentTypeId) async {
    try {
      await _dio.delete('/api/mobile/teams/$teamId/documents', data: {'documentTypeId': documentTypeId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not remove the document.');
    }
  }
}

final documentsRepositoryProvider =
    Provider<DocumentsRepository>((ref) => DocumentsRepository(ref.watch(dioProvider)));

final teamDocumentsProvider = FutureProvider.autoDispose
    .family<List<DocumentItem>, String>((ref, teamId) => ref.watch(documentsRepositoryProvider).forTeam(teamId));

/// Key = category id ('' = every sport).
final documentTypesProvider = FutureProvider.autoDispose
    .family<List<DocumentType>, String>((ref, categoryId) =>
        ref.watch(documentsRepositoryProvider).types(categoryId.isEmpty ? null : categoryId));
