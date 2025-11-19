class Customer {
  final String id;
  final String name;
  final String contactNumber;
  final String status;
  final dynamic info;
  final String? lastVisit;
  final String points;
  final String visits;
  final String? fingerprintId;
  final String? fingerprintStatus;

  Customer({
    required this.id, 
    required this.name, 
    required this.contactNumber,
    required this.status,
    this.info,
    this.lastVisit,
    required this.points,
    required this.visits,
    this.fingerprintId,
    this.fingerprintStatus,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    // Extract fingerprint data if present
    final fingerprintData = json['fingerprint'] as Map<String, dynamic>?;
    String? fingerprintId;
    String? fingerprintStatus;
    
    if (fingerprintData != null) {
      fingerprintId = fingerprintData['id']?.toString();
      fingerprintStatus = fingerprintData['status']?.toString();
    }
    
    return Customer(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      contactNumber: json['contactNumber'] ?? '',
      status: json['status'] ?? '',
      info: json['info'],
      lastVisit: json['lastVisit'],
      points: json['points'] ?? '0',
      visits: json['visits'] ?? '0',
      fingerprintId: fingerprintId,
      fingerprintStatus: fingerprintStatus,
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
      if (fingerprintId != null || fingerprintStatus != null)
        'fingerprint': {
          if (fingerprintId != null) 'id': fingerprintId,
          if (fingerprintStatus != null) 'status': fingerprintStatus,
        },
    };
  }
}