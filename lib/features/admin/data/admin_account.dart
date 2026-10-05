import 'package:nafir/features/auth/data/auth_models.dart';

class AdminAccount {
  const AdminAccount({required this.user, required this.createdAt});

  factory AdminAccount.fromJson(Map<String, dynamic> json) => AdminAccount(
        user: AuthUser.fromJson(json),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final AuthUser user;
  final DateTime createdAt;
}

typedef AdminAccountPage = ({List<AdminAccount> accounts, bool hasMore});

abstract interface class AdminApi {
  Future<AdminAccountPage> listAccounts(String token,
      {String query = '', int offset = 0});
  Future<AdminAccount> setAccountVerification(
      String token, String accountId, bool verified);
}
