import os
from typing import Optional
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa, padding as rsa_padding
from cryptography.hazmat.primitives import serialization
import logging
from typing import Tuple, Optional # Added Optional

logger = logging.getLogger(__name__)

# --- Symmetric Encryption (AES-GCM for Messages & Key Wrapping) ---

def generate_aes_key(key_size: int = 32) -> bytes:
    """Generates a random AES key (e.g., 32 bytes for AES-256)."""
    return os.urandom(key_size)

def encrypt_aes_gcm(key: bytes, plaintext: str | bytes) -> bytes:
    """
    Encrypts plaintext using AES-GCM.
    Returns bytes containing 'iv + ciphertext + tag'.
    """
    try:
        # Convert to bytes if input is string
        plaintext_bytes = plaintext.encode('utf-8') if isinstance(plaintext, str) else plaintext
        iv = os.urandom(12)  # GCM recommended IV size is 12 bytes
        encryptor = Cipher(
            algorithms.AES(key),
            modes.GCM(iv),
            backend=default_backend()
        ).encryptor()

        # GCM does not require padding
        ciphertext = encryptor.update(plaintext_bytes) + encryptor.finalize()
        tag = encryptor.tag # GCM tag for authentication

        # Combine IV, ciphertext, and tag
        return iv + ciphertext + tag
    except Exception as e:
        logger.error(f"AES-GCM encryption failed: {e}", exc_info=True)
        raise ValueError("Encryption failed") from e

def decrypt_aes_gcm(key: bytes, base64_ciphertext: str) -> str:
    """
    Decrypts Base64 encoded AES-GCM ciphertext ('iv + ciphertext + tag').
    Returns the original plaintext string.
    """
    try:
        combined = base64.b64decode(base64_ciphertext.encode('utf-8'))

        # Extract IV, ciphertext, and tag
        iv = combined[:12]
        tag = combined[-16:] # GCM tag is typically 16 bytes
        ciphertext = combined[12:-16]

        decryptor = Cipher(
            algorithms.AES(key),
            modes.GCM(iv, tag),
            backend=default_backend()
        ).decryptor()

        decrypted_bytes = decryptor.update(ciphertext) + decryptor.finalize()
        return decrypted_bytes.decode('utf-8')
    except Exception as e:
        logger.error(f"AES-GCM decryption failed: {e}", exc_info=True)
        # Consider specific exceptions like InvalidTag for authentication failures
        raise ValueError("Decryption failed or message integrity check failed") from e


# --- Asymmetric Encryption (RSA - Primarily for Key Exchange/Wrapping) ---
# Note: Direct RSA encryption is usually limited by key size.
# It's better suited for encrypting small data like symmetric keys.

def load_public_key_from_pem(pem_data: str) -> rsa.RSAPublicKey:
    """Loads an RSA public key from PEM formatted string."""
    try:
        public_key = serialization.load_pem_public_key(
            pem_data.encode('utf-8'),
            backend=default_backend()
        )
        if not isinstance(public_key, rsa.RSAPublicKey):
             raise TypeError("Loaded key is not an RSA public key")
        return public_key
    except Exception as e:
        logger.error(f"Failed to load public key from PEM: {e}", exc_info=True)
        raise ValueError("Invalid public key format") from e

def load_private_key_from_pem(pem_data: str, password: Optional[str] = None) -> rsa.RSAPrivateKey:
    """Loads an RSA private key from PEM formatted string."""
    try:
        private_key = serialization.load_pem_private_key(
            pem_data.encode('utf-8'),
            password=password.encode('utf-8') if password else None,
            backend=default_backend()
        )
        if not isinstance(private_key, rsa.RSAPrivateKey):
             raise TypeError("Loaded key is not an RSA private key")
        return private_key
    except Exception as e:
        logger.error(f"Failed to load private key from PEM: {e}", exc_info=True)
        raise ValueError("Invalid private key format or incorrect password") from e


def encrypt_with_rsa_public_key(public_key: rsa.RSAPublicKey, data: bytes) -> bytes:
    """Encrypts data using an RSA public key (OAEP padding recommended)."""
    try:
        ciphertext = public_key.encrypt(
            data,
            rsa_padding.OAEP(
                mgf=rsa_padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None
            )
        )
        return ciphertext
    except Exception as e:
        logger.error(f"RSA encryption failed: {e}", exc_info=True)
        raise ValueError("RSA encryption failed") from e


def decrypt_with_rsa_private_key(private_key: rsa.RSAPrivateKey, ciphertext: bytes) -> bytes:
    """Decrypts data using an RSA private key (OAEP padding recommended)."""
    try:
        plaintext = private_key.decrypt(
            ciphertext,
            rsa_padding.OAEP(
                mgf=rsa_padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None
            )
        )
        return plaintext
    except Exception as e:
        logger.error(f"RSA decryption failed: {e}", exc_info=True)
        raise ValueError("RSA decryption failed") from e


# --- RSA Key Pair Generation ---

def generate_rsa_key_pair(key_size: int = 2048) -> rsa.RSAPrivateKey:
    """Generates a new RSA private key."""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=key_size,
        backend=default_backend()
    )
    return private_key

def serialize_private_key_to_pem(private_key: rsa.RSAPrivateKey, password: Optional[bytes] = None) -> bytes:
    """Serializes an RSA private key to PEM format (optionally encrypted)."""
    encryption_algorithm = serialization.NoEncryption()
    if password:
        # Use best available encryption - AES-256 GCM if possible, otherwise CBC
        # Note: Strong password needed for effective protection
         encryption_algorithm = serialization.BestAvailableEncryption(password)

    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=encryption_algorithm
    )
    return pem

def serialize_public_key_to_pem(public_key: rsa.RSAPublicKey) -> bytes:
    """Serializes an RSA public key to PEM format."""
    pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return pem


# --- Key Derivation (Example using PBKDF2) ---

def derive_key_from_password(password: str, salt: bytes, key_length: int = 32) -> Tuple[bytes, bytes]:
    """
    Derives a key from a password using PBKDF2.
    Generates a new salt if none is provided.
    Returns the derived key and the salt used (hex encoded).
    """
    if not salt:
        salt = os.urandom(16) # Generate a salt if none provided
        logger.debug("Generated new salt for key derivation.")

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=key_length,
        salt=salt,
        iterations=480000, # NIST recommended minimum iterations
        backend=default_backend()
    )
    key = kdf.derive(password.encode('utf-8'))
    logger.debug(f"Derived key of length {len(key)} using salt {salt.hex()}")
    return key, salt # Return key and the salt used

# Example usage (can be removed or kept for testing):
if __name__ == '__main__':
    # --- RSA Key Generation Example ---
    print("\n--- RSA Key Generation ---")
    priv_key = generate_rsa_key_pair()
    pub_key = priv_key.public_key()

    # Serialize without password
    priv_pem_unencrypted = serialize_private_key_to_pem(priv_key)
    pub_pem = serialize_public_key_to_pem(pub_key)
    print("Public Key PEM:\n", pub_pem.decode())
    print("Private Key PEM (Unencrypted):\n", priv_pem_unencrypted.decode())

    # Serialize with password
    key_password = b"mysecretpassword"
    priv_pem_encrypted = serialize_private_key_to_pem(priv_key, password=key_password)
    print("Private Key PEM (Encrypted):\n", priv_pem_encrypted.decode())

    # Load back
    loaded_pub = load_public_key_from_pem(pub_pem.decode())
    loaded_priv_unenc = load_private_key_from_pem(priv_pem_unencrypted.decode())
    loaded_priv_enc = load_private_key_from_pem(priv_pem_encrypted.decode(), password=key_password.decode())
    print("Keys loaded successfully.")
    assert isinstance(loaded_pub, rsa.RSAPublicKey)
    assert isinstance(loaded_priv_unenc, rsa.RSAPrivateKey)
    assert isinstance(loaded_priv_enc, rsa.RSAPrivateKey)

    # --- Key Derivation Example ---
    print("\n--- Key Derivation ---")
    password_str = "user-password-123"
    # Derive key with generated salt
    derived_key1, salt1 = derive_key_from_password(password_str, salt=None)
    print(f"Derived Key 1 (hex): {derived_key1.hex()}")
    print(f"Salt 1 (hex): {salt1.hex()}")
    # Derive key again with the same salt (should produce the same key)
    derived_key2, salt2 = derive_key_from_password(password_str, salt=salt1)
    print(f"Derived Key 2 (hex): {derived_key2.hex()}")
    print(f"Salt 2 (hex): {salt2.hex()}")
    assert derived_key1 == derived_key2
    assert salt1 == salt2
    print("Key derivation test passed!")


    # --- AES-GCM Example (using derived key) ---
    print("\n--- AES-GCM with Derived Key ---")
    aes_key = derived_key1 # Use the key derived from password
    # AES-GCM Example
    aes_key = generate_aes_key()
    print(f"Generated AES Key (hex): {aes_key.hex()}")
    original_text = "This is a secret message for AES-GCM!"
    encrypted_b64 = encrypt_aes_gcm(aes_key, original_text)
    print(f"Encrypted (Base64): {encrypted_b64}")
    decrypted_text = decrypt_aes_gcm(aes_key, encrypted_b64)
    print(f"Decrypted: {decrypted_text}")
    assert original_text == decrypted_text
    print("AES-GCM Test Passed!")

    # Attempt decryption with wrong key (should fail)
    wrong_key = generate_aes_key()
    try:
        decrypt_aes_gcm(wrong_key, encrypted_b64)
        print("ERROR: Decryption with wrong key succeeded!")
    except ValueError as e:
        print(f"Decryption with wrong key failed as expected: {e}")

    # Attempt decryption with tampered data (should fail)
    tampered_b64 = encrypted_b64[:-5] + "abcde" # Modify the tag part
    try:
        decrypt_aes_gcm(aes_key, tampered_b64)
        print("ERROR: Decryption with tampered data succeeded!")
    except ValueError as e:
        print(f"Decryption with tampered data failed as expected: {e}")

class ServerEncryption:
    """Handles server-side encryption operations."""
    
    def __init__(self):
        """Initialize server encryption with a new RSA key pair."""
        self._private_key = generate_rsa_key_pair()
        self._public_key = self._private_key.public_key()
        logger.info("Server encryption initialized with new RSA key pair")

    def get_public_key_pem(self) -> str:
        """Returns the server's public key in PEM format."""
        try:
            pem_bytes = serialize_public_key_to_pem(self._public_key)
            return pem_bytes.decode('utf-8')
        except Exception as e:
            logger.error(f"Failed to get public key PEM: {e}")
            raise ValueError("Failed to get public key PEM") from e

    def encrypt_for_client(self, data: str | bytes, client_public_key_pem: str) -> dict[str, str]:
        """
        Encrypts data for a specific client using their public key.
        
        Args:
            data: The data to encrypt (string or bytes)
            client_public_key_pem: The client's public key in PEM format
            
        Returns:
            dict: Contains encrypted_content, encrypted_key, iv, and tag
        """
        try:
            # Generate a random AES key for this message
            aes_key = generate_aes_key()
            
            # Load the client's public key
            client_public_key = load_public_key_from_pem(client_public_key_pem)
            
            # Encrypt the AES key with the client's public key
            encrypted_key = encrypt_with_rsa_public_key(client_public_key, aes_key)
            
            # Encrypt the actual data with AES-GCM
            encrypted_data = encrypt_aes_gcm(aes_key, data)
            
            # The encrypted_data from encrypt_aes_gcm is already base64 encoded and
            # contains the IV and tag
            
            return {
                "encrypted_content": encrypted_data,
                "encrypted_key": base64.b64encode(encrypted_key).decode('utf-8')
            }
        except Exception as e:
            logger.error(f"Failed to encrypt for client: {e}")
            raise ValueError("Failed to encrypt for client") from e

    def decrypt_from_client(self, encrypted_data: dict[str, str]) -> str:
        """
        Decrypts data that was encrypted with the server's public key.
        
        Args:
            encrypted_data: Dict containing encrypted_content, encrypted_key, iv, and tag
            
        Returns:
            str: The decrypted content
        """
        try:
            # Decode the encrypted AES key
            encrypted_key = base64.b64decode(encrypted_data["encrypted_key"])
            
            # Decrypt the AES key using the server's private key
            aes_key = decrypt_with_rsa_private_key(self._private_key, encrypted_key)
            
            # Decrypt the content using the AES key
            decrypted_content = decrypt_aes_gcm(aes_key, encrypted_data["encrypted_content"])
            
            return decrypted_content
        except Exception as e:
            logger.error(f"Failed to decrypt from client: {e}")
            raise ValueError("Failed to decrypt from client") from e

# Create a singleton instance
server_encryption = ServerEncryption()
