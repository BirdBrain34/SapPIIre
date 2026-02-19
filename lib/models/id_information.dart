class IdInformation {
  final String firstName;
  final String middleName;
  final String lastName;
  final String address;
  final String dateOfBirth;

  IdInformation({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.address = '',
    this.dateOfBirth = '',
  });

  bool get hasValidName => firstName.isNotEmpty && lastName.isNotEmpty;
}