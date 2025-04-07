"""Server-side encryption utilities."""

import os
import base64
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
import logging
import hashlib # Import hashlib

logger = logging.getLogger(__name__)

class ServerEncryption:
    """Handles server-side encryption for LLM communication."""
    
    def __init__(self):
        """Initialize the encryption service with a server key pair."""
        self._private_key = None
        self._public_key = None
        self._key_dir = Path("keys")
        self._private_key_path = self._key_dir / "server_private_key.pem"
        self._public_key_path = self._key_dir / "server_public_key.pem"
        self._initialize_keys()
    
    def _initialize_keys(self):
        """Initialize RSA key pair for the server."""
        try:
            # Create keys directory if it doesn't exist
            self._key_dir.mkdir(exist_ok=True)
            
            # Try to load existing keys
            if self._private_key_path.exists() and self._public_key_path.exists():
                logger.info("Loading existing server key pair")
                with open(self._private_key_path, 'rb') as f:
                    self._private_key = serialization.load_pem_private_key(
                        f.read(),
                        password=None,
                        backend=default_backend()
                    )
                with open(self._public_key_path, 'rb') as f:
                    self._public_key = serialization.load_pem_public_key(
                        f.read(),
                        backend=default_backend()
                    )
            else:
                # Generate new key pair
                logger.info("Generating new server key pair")
                self._private_key = rsa.generate_private_key(
                    public_exponent=65537,
                    key_size=2048,
                    backend=default_backend()
                )
                self._public_key = self._private_key.public_key()
                
                # Save keys to disk
                with open(self._private_key_path, 'wb') as f:
                    f.write(self._private_key.private_bytes(
                        encoding=serialization.Encoding.PEM,
                        format=serialization.PrivateFormat.PKCS8,
                        encryption_algorithm=serialization.NoEncryption()
                    ))
                with open(self._public_key_path, 'wb') as f:
                    f.write(self._public_key.public_bytes(
                        encoding=serialization.Encoding.PEM,
                        format=serialization.PublicFormat.SubjectPublicKeyInfo
                    ))
                logger.info("Server key pair saved to disk")

            # --- Log Public Key Fingerprint ---
            if self._public_key:
                try:
                    public_key_der = self._public_key.public_bytes(
                        encoding=serialization.Encoding.DER,
                        format=serialization.PublicFormat.SubjectPublicKeyInfo
                    )
                    fingerprint = hashlib.sha256(public_key_der).hexdigest()
                    logger.info(f"Initialized/Loaded Server Public Key Fingerprint (SHA256): {fingerprint}")
                except Exception as log_e:
                    logger.warning(f"Could not calculate/log server public key fingerprint: {log_e}")
            # --- End Log ---

        except Exception as e:
            logger.error(f"Error initializing server keys: {e}")
            raise

    def get_public_key_pem(self) -> str:
        """Get server's public key in PEM format."""
        return self._public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode('utf-8')
    
    def encrypt_for_client(self, message: str, client_public_key_pem: str) -> dict:
        """Encrypt a message for a specific client."""
        # Generate AES key for this message
        aes_key = os.urandom(32)  # 256-bit key
        iv = os.urandom(16)  # 128-bit IV for AES-GCM
        
        # Load client's public key
        client_public_key = serialization.load_pem_public_key(
            client_public_key_pem.encode(),
            backend=default_backend()
        )
        
        # Encrypt AES key with client's public key
        encrypted_key = client_public_key.encrypt(
            aes_key,
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None
            )
        )
        
        # Encrypt message with AES-GCM
        cipher = Cipher(
            algorithms.AES(aes_key),
            modes.GCM(iv),
            backend=default_backend()
        )
        encryptor = cipher.encryptor()
        ciphertext = encryptor.update(message.encode()) + encryptor.finalize()
        
        return {
            'encrypted_content': base64.b64encode(ciphertext).decode('utf-8'),
            'encrypted_key': base64.b64encode(encrypted_key).decode('utf-8'),
            'iv': base64.b64encode(iv).decode('utf-8'),
            'tag': base64.b64encode(encryptor.tag).decode('utf-8')
        }
    
    def decrypt_from_client(self, encrypted_data: dict) -> str:
        """Decrypt a message from a client using server's private key."""
        try:
            # Decode components
            ciphertext = base64.b64decode(encrypted_data['encrypted_content'])
            encrypted_key = base64.b64decode(encrypted_data['encrypted_key'])
            iv = base64.b64decode(encrypted_data['iv'])
            tag = base64.b64decode(encrypted_data['tag'])

            # --- Add Detailed Logging Before Decryption ---
            logger.debug(f"Attempting to decrypt AES key. Encrypted key length: {len(encrypted_key)}")
            # Avoid logging the actual key bytes for security, but log presence/length
            # logger.debug(f"Encrypted AES Key (base64): {encrypted_data['encrypted_key']}") # Potentially sensitive

            # Decrypt AES key with server's private key
            try:
                aes_key = self._private_key.decrypt(
                    encrypted_key,
                    padding.OAEP(
                        mgf=padding.MGF1(algorithm=hashes.SHA256()),
                        algorithm=hashes.SHA256(),
                        label=None
                    )
                )
                logger.debug(f"AES key decrypted successfully. AES key length: {len(aes_key)}")
            except ValueError as rsa_e:
                 logger.error(f"RSA decryption of AES key failed: {rsa_e}", exc_info=True)
                 # Add more context if possible
                 logger.debug(f"Server private key type: {type(self._private_key)}")
                 raise ValueError(f"Failed to decrypt AES key: {str(rsa_e)}") # Re-raise specific error

            # Decrypt message with AES-GCM
            logger.debug(f"Attempting AES-GCM decryption. IV length: {len(iv)}, Tag length: {len(tag)}, Ciphertext length: {len(ciphertext)}")
            # Avoid logging actual ciphertext/iv/tag unless absolutely necessary for debugging specific corruption
            # logger.debug(f"IV (base64): {encrypted_data['iv']}")
            # logger.debug(f"Tag (base64): {encrypted_data['tag']}")
            # logger.debug(f"Ciphertext (base64): {encrypted_data['encrypted_content']}")

            cipher = Cipher(
                algorithms.AES(aes_key),
                modes.GCM(iv, tag), # Pass tag here for authentication
                backend=default_backend()
            )
            decryptor = cipher.decryptor()
            # Authenticate and decrypt
            decrypted_bytes = decryptor.update(ciphertext) + decryptor.finalize()
            logger.debug("AES-GCM decryption successful.")
            return decrypted_bytes.decode()

        except ValueError as ve: # Catch specific ValueErrors from decryption steps
             logger.error(f"Decryption step failed: {ve}", exc_info=True)
             raise ValueError(f"Failed to decrypt message: {str(ve)}") # Re-raise with context
        except Exception as e:
            # Catch any other unexpected errors during decoding/decryption
            logger.error(f"Unexpected error during decryption: {e}", exc_info=True)
            raise ValueError(f"Failed to decrypt message: {str(e)}")

# Create a singleton instance
server_encryption = ServerEncryption()
