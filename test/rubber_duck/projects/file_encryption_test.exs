defmodule RubberDuck.Projects.FileEncryptionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Projects.FileEncryption
  
  describe "encrypt_content/3 and decrypt_content/3" do
    test "encrypts and decrypts content successfully" do
      content = "This is sensitive data that needs encryption"
      secret = "test_secret_key_123"
      
      # Encrypt
      assert {:ok, encrypted} = FileEncryption.encrypt_content(content, secret)
      
      # Verify encrypted is different from original
      assert encrypted != content
      assert byte_size(encrypted) > byte_size(content)
      
      # Decrypt
      assert {:ok, decrypted} = FileEncryption.decrypt_content(encrypted, secret)
      assert decrypted == content
    end
    
    test "fails to decrypt with wrong secret" do
      content = "Secret message"
      correct_secret = "correct_key"
      wrong_secret = "wrong_key"
      
      {:ok, encrypted} = FileEncryption.encrypt_content(content, correct_secret)
      
      assert {:error, :decryption_failed} = 
        FileEncryption.decrypt_content(encrypted, wrong_secret)
    end
    
    test "includes metadata in authenticated data" do
      content = "Data with metadata"
      secret = "test_key"
      metadata1 = %{user: "alice", timestamp: 123}
      metadata2 = %{user: "bob", timestamp: 456}
      
      # Encrypt with metadata1
      {:ok, encrypted} = FileEncryption.encrypt_content(content, secret, metadata1)
      
      # Can decrypt with same metadata
      assert {:ok, ^content} = FileEncryption.decrypt_content(encrypted, secret, metadata1)
      
      # Fails with different metadata (authentication failure)
      assert {:error, :decryption_failed} = 
        FileEncryption.decrypt_content(encrypted, secret, metadata2)
    end
    
    test "handles empty content" do
      content = ""
      secret = "test_key"
      
      assert {:ok, encrypted} = FileEncryption.encrypt_content(content, secret)
      assert {:ok, ""} = FileEncryption.decrypt_content(encrypted, secret)
    end
    
    test "handles binary content" do
      content = <<0, 1, 2, 3, 255, 254, 253, 252>>
      secret = "test_key"
      
      assert {:ok, encrypted} = FileEncryption.encrypt_content(content, secret)
      assert {:ok, ^content} = FileEncryption.decrypt_content(encrypted, secret)
    end
  end
  
  describe "encrypt_file/3 and decrypt_file/3" do
    setup do
      temp_dir = Path.join(System.tmp_dir!(), "encryption_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(temp_dir)
      
      on_exit(fn -> File.rm_rf!(temp_dir) end)
      
      %{temp_dir: temp_dir, secret: "file_encryption_secret"}
    end
    
    test "encrypts and decrypts a file", %{temp_dir: temp_dir, secret: secret} do
      # Create test file
      original_path = Path.join(temp_dir, "test.txt")
      original_content = "This is a test file for encryption"
      File.write!(original_path, original_content)
      
      # Encrypt file
      assert {:ok, encrypted_path} = FileEncryption.encrypt_file(original_path, secret)
      assert encrypted_path == original_path <> ".enc"
      assert File.exists?(encrypted_path)
      
      # Original file should still exist
      assert File.exists?(original_path)
      
      # Encrypted file should be different
      encrypted_content = File.read!(encrypted_path)
      assert encrypted_content != original_content
      assert String.starts_with?(encrypted_content, "ENC1")
      
      # Decrypt file
      decrypted_path = Path.join(temp_dir, "decrypted.txt")
      File.rename!(encrypted_path, decrypted_path <> ".enc")
      
      assert {:ok, ^decrypted_path} = 
        FileEncryption.decrypt_file(decrypted_path <> ".enc", secret)
      
      assert File.read!(decrypted_path) == original_content
    end
    
    test "deletes original file when requested", %{temp_dir: temp_dir, secret: secret} do
      original_path = Path.join(temp_dir, "sensitive.txt")
      File.write!(original_path, "Sensitive data")
      
      assert {:ok, encrypted_path} = 
        FileEncryption.encrypt_file(original_path, secret, delete_original: true)
      
      assert File.exists?(encrypted_path)
      assert not File.exists?(original_path)
    end
    
    test "deletes encrypted file when requested", %{temp_dir: temp_dir, secret: secret} do
      original_path = Path.join(temp_dir, "data.txt")
      File.write!(original_path, "Some data")
      
      {:ok, encrypted_path} = FileEncryption.encrypt_file(original_path, secret)
      
      assert {:ok, ^original_path} = 
        FileEncryption.decrypt_file(encrypted_path, secret, delete_encrypted: true)
      
      assert File.exists?(original_path)
      assert not File.exists?(encrypted_path)
    end
  end
  
  describe "key management" do
    test "generate_key creates random keys" do
      key1 = FileEncryption.generate_key()
      key2 = FileEncryption.generate_key()
      
      assert byte_size(key1) == 32  # 256 bits
      assert byte_size(key2) == 32
      assert key1 != key2
    end
    
    test "derive_key creates consistent keys from secret and salt" do
      secret = "my_secret_password"
      salt1 = :crypto.strong_rand_bytes(32)
      salt2 = :crypto.strong_rand_bytes(32)
      
      # Same secret and salt produce same key
      key1a = FileEncryption.derive_key(secret, salt1)
      key1b = FileEncryption.derive_key(secret, salt1)
      assert key1a == key1b
      
      # Different salt produces different key
      key2 = FileEncryption.derive_key(secret, salt2)
      assert key1a != key2
      
      # Different secret produces different key
      key3 = FileEncryption.derive_key("different_secret", salt1)
      assert key1a != key3
    end
  end
  
  describe "encrypted?/1" do
    setup do
      temp_dir = Path.join(System.tmp_dir!(), "encryption_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(temp_dir)
      
      on_exit(fn -> File.rm_rf!(temp_dir) end)
      
      %{temp_dir: temp_dir}
    end
    
    test "detects encrypted files", %{temp_dir: temp_dir} do
      secret = "test_secret"
      
      # Create and encrypt a file
      plain_path = Path.join(temp_dir, "plain.txt")
      File.write!(plain_path, "Plain text content")
      
      {:ok, encrypted_path} = FileEncryption.encrypt_file(plain_path, secret)
      
      assert FileEncryption.encrypted?(encrypted_path)
      assert not FileEncryption.encrypted?(plain_path)
    end
    
    test "detects non-encrypted files", %{temp_dir: temp_dir} do
      # Text file
      text_path = Path.join(temp_dir, "text.txt")
      File.write!(text_path, "This is plain text")
      assert not FileEncryption.encrypted?(text_path)
      
      # Binary file with pattern
      binary_path = Path.join(temp_dir, "binary.bin")
      File.write!(binary_path, <<0, 1, 2, 3, 0, 1, 2, 3>>)
      assert not FileEncryption.encrypted?(binary_path)
    end
  end
  
  describe "error handling" do
    test "handles invalid encrypted data" do
      secret = "test_key"
      
      # Too short
      assert {:error, :invalid_encrypted_data} = 
        FileEncryption.decrypt_content("short", secret)
      
      # Corrupted data
      assert {:error, :decryption_failed} = 
        FileEncryption.decrypt_content(String.duplicate("x", 100), secret)
    end
  end
end