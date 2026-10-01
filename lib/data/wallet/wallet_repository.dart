import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart';

/// Group wallet management (admins): balance, withdrawals + approvals, ledger,
/// and provider onboarding. Bank onboarding itself is the provider's hosted
/// page (or our web form for Paystack/Flutterwave) opened in the browser.
class WalletRepository {
  WalletRepository(this._dio);
  final Dio _dio;

  String _path(String groupId) => '/api/mobile/groups/$groupId/wallet';

  Future<WalletOverview> overview(String groupId) async {
    try {
      final res =
          await _dio.get(_path(groupId), queryParameters: {'view': 'overview'});
      return WalletOverview.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the wallet.');
    }
  }

  Future<WithdrawalsPage> withdrawals(String groupId) async {
    try {
      final res = await _dio
          .get(_path(groupId), queryParameters: {'view': 'withdrawals'});
      return WithdrawalsPage.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load withdrawals.');
    }
  }

  Future<List<LedgerEntry>> ledger(String groupId, {int limit = 50}) async {
    try {
      final res = await _dio.get(_path(groupId),
          queryParameters: {'view': 'ledger', 'limit': limit});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          LedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load activity.');
    }
  }

  /// Fire-and-forget: asks the server to email the caller the web plans /
  /// billing link. The app never links out to purchases itself (app-store
  /// rules, kept uniform across platforms) — out-of-app email is allowed.
  /// Server-side throttled; failures are deliberately swallowed.
  Future<void> requestPlanEmail(String groupId,
      {String topic = 'wallet'}) async {
    try {
      await _dio
          .post(_path(groupId), data: {'action': 'plan-email', 'topic': topic});
    } catch (_) {
      // Silent by design — the app never surfaces this flow.
    }
  }

  Future<void> requestWithdrawal(String groupId,
      {required String paymentAccountId,
      required int amountMinor,
      String? reason}) async {
    try {
      await _dio.post(_path(groupId), data: {
        'action': 'withdraw',
        'paymentAccountId': paymentAccountId,
        'amount': amountMinor,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not request the withdrawal.');
    }
  }

  Future<void> approve(String groupId, String withdrawalId,
      {String? note}) async {
    try {
      await _dio.post(_path(groupId), data: {
        'action': 'approve',
        'withdrawalId': withdrawalId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not approve.');
    }
  }

  Future<void> reject(String groupId, String withdrawalId,
      {String? note}) async {
    try {
      await _dio.post(_path(groupId), data: {
        'action': 'reject',
        'withdrawalId': withdrawalId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not reject.');
    }
  }

  /// Reconcile with the provider. Returns fresh progress (with an onboarding
  /// URL when the provider is still waiting on the organizer).
  Future<OnboardingProgress> refreshStatus(String groupId) async {
    try {
      final res = await _dio.post(_path(groupId), data: {'action': 'refresh'});
      return OnboardingProgress.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not refresh the status.');
    }
  }

  /// A link to continue the provider's hosted onboarding (null when done).
  Future<String?> resumeOnboarding(String groupId) async {
    try {
      final res = await _dio.post(_path(groupId), data: {'action': 'resume'});
      final d = Map<String, dynamic>.from(res.data as Map);
      return d['onboardingUrl'] as String?;
    } catch (e) {
      throw apiError(e, fallback: 'Could not continue setup.');
    }
  }

  /// Who pays the fees (one-time group setting) with a worked example.
  Future<FeeSetting> feeSetting(String groupId) async {
    try {
      final res =
          await _dio.get(_path(groupId), queryParameters: {'view': 'fees'});
      return FeeSetting.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the fee setting.');
    }
  }

  /// Choose who pays the fees — once. Support resets it.
  Future<void> setFeeBearer(String groupId, String bearer) async {
    try {
      await _dio.post(_path(groupId),
          data: {'action': 'fee-bearer', 'bearer': bearer});
    } catch (e) {
      throw apiError(e, fallback: 'Could not save the fee setting.');
    }
  }

  /// What buyers pay and the group receives for [priceMinor].
  Future<FeeQuote> feeQuote(String groupId, int priceMinor) async {
    try {
      final res = await _dio.get(_path(groupId),
          queryParameters: {'view': 'fee-quote', 'price': priceMinor});
      return FeeQuote.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not work out the fees.');
    }
  }
}

final walletRepositoryProvider = Provider<WalletRepository>(
    (ref) => WalletRepository(ref.watch(dioProvider)));

final walletOverviewProvider = FutureProvider.autoDispose
    .family<WalletOverview, String>((ref, groupId) =>
        ref.watch(walletRepositoryProvider).overview(groupId));

final walletWithdrawalsProvider = FutureProvider.autoDispose
    .family<WithdrawalsPage, String>((ref, groupId) =>
        ref.watch(walletRepositoryProvider).withdrawals(groupId));

final walletLedgerProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, String>(
        (ref, groupId) => ref.watch(walletRepositoryProvider).ledger(groupId));

final feeSettingProvider = FutureProvider.autoDispose
    .family<FeeSetting, String>((ref, groupId) =>
        ref.watch(walletRepositoryProvider).feeSetting(groupId));
