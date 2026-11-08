import 'package:flutter/foundation.dart';

enum UserRole {
  owner,
  manager,
  cashier,
  worker,
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String username;
  final String fullName;
  final UserRole role;

  bool get isOwner => role == UserRole.owner;
  bool get isManager => role == UserRole.manager || isOwner;
  bool get isCashier => role == UserRole.cashier || isManager;

  bool get canViewFinancialReports => isOwner || isManager;
  bool get canManageProducts => isOwner || isManager;
  bool get canManageWorkers => isOwner;
  bool get canManageSettings => isOwner;
  bool get canProcessSales => true;
}

class UserSession extends ChangeNotifier {
  UserSession._();
  static final UserSession instance = UserSession._();

  UserProfile _currentUser = UserProfile(
    id: 'local-owner',
    username: 'owner',
    fullName: 'Business Owner',
    role: UserRole.owner,
  );

  UserProfile get currentUser => _currentUser;

  void login({
    required String id,
    required String username,
    required String fullName,
    required UserRole role,
  }) {
    _currentUser = UserProfile(
      id: id,
      username: username,
      fullName: fullName,
      role: role,
    );
    notifyListeners();
  }

  void switchUser(UserProfile user) {
    _currentUser = user;
    notifyListeners();
  }
}
