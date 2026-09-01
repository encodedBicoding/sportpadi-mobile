import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';

final myGroupsProvider = FutureProvider.autoDispose<List<GroupSummary>>(
  (ref) => ref.watch(groupsRepositoryProvider).myGroups(),
);

/// Every group, for the Groups tab's Discover section. The screen filters out
/// groups the viewer already belongs to.
final discoverGroupsProvider = FutureProvider.autoDispose<List<GroupSummary>>(
  (ref) => ref.watch(groupsRepositoryProvider).discoverGroups(),
);

final groupProvider = FutureProvider.autoDispose.family<GroupDetail, String>(
  (ref, id) => ref.watch(groupsRepositoryProvider).group(id),
);
