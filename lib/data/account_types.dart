/// "What best describes you", asked at registration and saved on the account
/// as `users/{uid}.buyerType` or `farmerType`. The English text is what is
/// saved; the screens show it in the app's language.
const List<String> kBuyerTypes = [
  'Individual Consumer',
  'Restaurant / Food Business Owner',
  'Reseller / Trader',
  'Retail Store Owner',
  'Market Vendor',
  'Other',
];

const List<String> kFarmerTypes = [
  'Crop Farmer',
  'Livestock Farmer',
  'Both Crop and Livestock',
];

/// The buyers who usually order in bulk: they see the wholesale price first.
const Set<String> kWholesaleBuyerTypes = {
  'Restaurant / Food Business Owner',
  'Reseller / Trader',
  'Retail Store Owner',
  'Market Vendor',
};

/// The category the Admin's commodity list keeps animals under.
const String kLivestockCategory = 'Livestock';

/// What an older account, which was never asked, shows as.
const String kAccountTypeNotSpecified = 'Not specified';

/// The `users/{uid}` field that holds [role]'s answer.
String accountTypeField(String role) =>
    role == 'farmer' ? 'farmerType' : 'buyerType';

/// The saved answer of the account [profile], or null if there is none.
String? accountTypeOf(Map<String, dynamic> profile) {
  final role = (profile['role'] ?? '').toString();
  final saved = (profile[accountTypeField(role)] ?? '').toString().trim();
  return saved.isEmpty ? null : saved;
}

/// [names] with the ones matching [farmerType] first: animals for a Livestock
/// Farmer, crops for a Crop Farmer. It only changes the order, so a farmer
/// can still post anything on the list.
List<String> orderForFarmerType(
  Iterable<String> names, {
  required String? farmerType,
  required String? Function(String name) categoryOf,
}) {
  final Set<String> matching;
  bool isLivestock(String name) => categoryOf(name) == kLivestockCategory;
  switch (farmerType) {
    case 'Livestock Farmer':
      matching = {
        for (final name in names)
          if (isLivestock(name)) name,
      };
    case 'Crop Farmer':
      matching = {
        for (final name in names)
          if (!isLivestock(name)) name,
      };
    default:
      return names.toList();
  }
  return [...matching, ...names.where((name) => !matching.contains(name))];
}
