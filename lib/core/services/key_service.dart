import 'package:cryptography/cryptography.dart';
import 'database_service.dart';

class KeyService {
  String? deviceId;
  String? deviceLabel;     // human-readable name e.g. "PC 1234" or "Mobile ab12"
  String? publicKeyHex;    // Ed25519 public key in hex — safe to share
  SimpleKeyPair? _keyPair;

  Future<void> init() async {
    final db = DatabaseService();
    final pkHex = await db.getConfig('private_key');
    final pubHex = await db.getConfig('public_key');
    
    final ed25519 = Ed25519();
    
    if (pkHex == null || pubHex == null) {
      // First launch - Generate new Ed25519 keys
      _keyPair = await ed25519.newKeyPair();
      final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();
      final publicKey = await _keyPair!.extractPublicKey();
      
      await db.setConfig('private_key', _bytesToHex(privateKeyBytes));
      await db.setConfig('public_key', _bytesToHex(publicKey.bytes));
    } else {
      // Re-load keys
      _keyPair = SimpleKeyPairData(
        _hexToBytes(pkHex),
        publicKey: SimplePublicKey(_hexToBytes(pubHex), type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
    }
    
    // Create Device ID by hashing the Public Key
    final publicKey = await _keyPair!.extractPublicKey();
    final sha256 = Sha256();
    final hash = await sha256.hash(publicKey.bytes);

    // Safe output representing Device/Room ID
    deviceId = _bytesToHex(hash.bytes).substring(0, 32);
    publicKeyHex = _bytesToHex(publicKey.bytes);  // exposed for QR pairing
  }

  // Cryptographic Utils
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
  
  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
