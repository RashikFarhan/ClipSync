class PeerDevice {
  final String peerId;
  final String peerName;
  final String publicKey;
  final DateTime lastSeen;
  final bool isOnline;
  /// True when this entry represents the current device (not a remote peer).
  final bool isSelf;

  const PeerDevice({
    required this.peerId,
    required this.peerName,
    required this.publicKey,
    required this.lastSeen,
    this.isOnline = false,
    this.isSelf = false,
  });

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'peer_name': peerName,
    'public_key': publicKey,
    'last_seen': lastSeen.millisecondsSinceEpoch,
  };

  factory PeerDevice.fromMap(Map<String, dynamic> map) => PeerDevice(
    peerId: map['peer_id'] as String,
    peerName: map['peer_name'] as String,
    publicKey: map['public_key'] as String,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen'] as int),
  );

  PeerDevice copyWith({
    String? peerId,
    String? peerName,
    String? publicKey,
    DateTime? lastSeen,
    bool? isOnline,
    bool? isSelf,
  }) => PeerDevice(
    peerId: peerId ?? this.peerId,
    peerName: peerName ?? this.peerName,
    publicKey: publicKey ?? this.publicKey,
    lastSeen: lastSeen ?? this.lastSeen,
    isOnline: isOnline ?? this.isOnline,
    isSelf: isSelf ?? this.isSelf,
  );
}
