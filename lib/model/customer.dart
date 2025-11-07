class Customer {
  final String id;
  final String name;
  final String contactNumber;
  final String status;
  final dynamic info;
  final String? lastVisit;
  final String points;
  final String visits;

  Customer({
    required this.id, 
    required this.name, 
    required this.contactNumber,
    required this.status,
    this.info,
    this.lastVisit,
    required this.points,
    required this.visits,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      contactNumber: json['contactNumber'] ?? '',
      status: json['status'] ?? '',
      info: json['info'],
      lastVisit: json['lastVisit'],
      points: json['points'] ?? '0',
      visits: json['visits'] ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id, 
      'name': name, 
      'contactNumber': contactNumber,
      'status': status,
      'info': info,
      'lastVisit': lastVisit,
      'points': points,
      'visits': visits,
    };
  }
}