defmodule RubberDuck.Projects.FileEncryption do
  @moduledoc """
  File encryption module for sensitive data protection.
  
  Provides AES-256-GCM encryption for files with:
  - Per-file encryption keys
  - Key derivation from project secrets
  - Secure key storage
  - Transparent encryption/decryption
  """
  
  require Logger
  
  @aead_algorithm :aes_256_gcm
  @key_size 32  # 256 bits
  @iv_size 16   # 128 bits
  @tag_size 16  # 128 bits
  @salt_size 32 # 256 bits
  
  @doc """
  Encrypts file content with a derived key.
  
  Returns {:ok, encrypted_data} where encrypted_data includes:
  - Salt (32 bytes)
  - IV (16 bytes)  
  - Tag (16 bytes)
  - Ciphertext (variable)
  """
  def encrypt_content(content, secret, metadata \\ %{}) do
    # Generate salt and IV
    salt = :crypto.strong_rand_bytes(@salt_size)
    iv = :crypto.strong_rand_bytes(@iv_size)
    
    # Derive key from secret and salt
    key = derive_key(secret, salt)
    
    # Add metadata to AAD (Additional Authenticated Data)
    aad = build_aad(metadata)
    
    # Encrypt
    case :crypto.crypto_one_time_aead(@aead_algorithm, key, iv, content, aad, true) do
      {ciphertext, tag} ->
        # Combine salt, iv, tag, and ciphertext
        encrypted = <<
          salt::binary-size(@salt_size),
          iv::binary-size(@iv_size),
          tag::binary-size(@tag_size),
          ciphertext::binary
        >>
        
        {:ok, encrypted}
        
      error ->
        {:error, {:encryption_failed, error}}
    end
  end
  
  @doc """
  Decrypts file content with a derived key.
  
  Returns {:ok, plaintext} or {:error, reason}
  """
  def decrypt_content(encrypted_data, secret, metadata \\ %{}) do
    with {:ok, parts} <- extract_parts(encrypted_data),
         {:ok, plaintext} <- do_decrypt(parts, secret, metadata) do
      {:ok, plaintext}
    end
  end
  
  @doc """
  Encrypts a file in place, creating an encrypted version.
  
  The encrypted file will have a .enc extension added.
  """
  def encrypt_file(path, secret, opts \\ []) do
    output_path = path <> ".enc"
    
    with {:ok, content} <- File.read(path),
         {:ok, encrypted} <- encrypt_content(content, secret, build_file_metadata(path)),
         :ok <- write_encrypted_file(output_path, encrypted, opts) do
      
      if Keyword.get(opts, :delete_original, false) do
        # Securely delete original file
        secure_delete(path)
      end
      
      {:ok, output_path}
    end
  end
  
  @doc """
  Decrypts a file, creating a decrypted version.
  
  Removes the .enc extension if present.
  """
  def decrypt_file(encrypted_path, secret, opts \\ []) do
    output_path = String.replace_suffix(encrypted_path, ".enc", "")
    
    with {:ok, file_content} <- File.read(encrypted_path),
         {:ok, encrypted} <- strip_header(file_content),
         {:ok, plaintext} <- decrypt_content(encrypted, secret, build_file_metadata(output_path)),
         :ok <- File.write(output_path, plaintext) do
      
      if Keyword.get(opts, :delete_encrypted, false) do
        File.rm(encrypted_path)
      end
      
      {:ok, output_path}
    end
  end
  
  @doc """
  Generates a random encryption key.
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_size)
  end
  
  @doc """
  Derives a key from a secret and salt using PBKDF2.
  """
  def derive_key(secret, salt) do
    iterations = 100_000
    :crypto.pbkdf2_hmac(:sha256, secret, salt, iterations, @key_size)
  end
  
  @doc """
  Checks if a file is encrypted by examining its header.
  """
  def encrypted?(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        # Read enough bytes to check structure
        header_size = @salt_size + @iv_size + @tag_size
        header = IO.binread(file, header_size)
        File.close(file)
        
        # Check if we have enough bytes and they look random
        byte_size(header) == header_size and high_entropy?(header)
        
      _ ->
        false
    end
  end
  
  # Private functions
  
  defp extract_parts(encrypted_data) when byte_size(encrypted_data) < 64 do
    {:error, :invalid_encrypted_data}
  end
  
  defp extract_parts(encrypted_data) do
    <<
      salt::binary-size(@salt_size),
      iv::binary-size(@iv_size),
      tag::binary-size(@tag_size),
      ciphertext::binary
    >> = encrypted_data
    
    {:ok, %{salt: salt, iv: iv, tag: tag, ciphertext: ciphertext}}
  end
  
  defp do_decrypt(%{salt: salt, iv: iv, tag: tag, ciphertext: ciphertext}, secret, metadata) do
    # Derive key
    key = derive_key(secret, salt)
    
    # Build AAD
    aad = build_aad(metadata)
    
    # Decrypt
    case :crypto.crypto_one_time_aead(@aead_algorithm, key, iv, ciphertext, aad, tag, false) do
      plaintext when is_binary(plaintext) ->
        {:ok, plaintext}
        
      :error ->
        {:error, :decryption_failed}
    end
  end
  
  defp build_aad(metadata) do
    # Convert metadata to deterministic binary format
    metadata
    |> Map.to_list()
    |> Enum.sort()
    |> :erlang.term_to_binary()
  end
  
  defp build_file_metadata(path) do
    # Don't include filename in metadata as it can change when file is moved
    # Only include extension as a type hint
    %{
      extension: Path.extname(path)
    }
  end
  
  defp write_encrypted_file(path, encrypted, opts) do
    # Add encryption marker header
    header = "ENC1"  # Version 1 encryption format
    full_data = header <> encrypted
    
    # Write with restricted permissions
    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, file} ->
        :ok = IO.binwrite(file, full_data)
        File.close(file)
        
        # Set restricted permissions (owner read/write only)
        if Keyword.get(opts, :restrict_permissions, true) do
          File.chmod!(path, 0o600)
        end
        
        :ok
        
      {:error, :eexist} ->
        {:error, :file_exists}
        
      error ->
        error
    end
  end
  
  defp secure_delete(path) do
    # Overwrite file with random data before deletion
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} ->
        # Overwrite with random data
        random_data = :crypto.strong_rand_bytes(size)
        File.write!(path, random_data)
        
        # Overwrite again with zeros
        zeros = :binary.copy(<<0>>, size)
        File.write!(path, zeros)
        
        # Finally delete
        File.rm!(path)
        :ok
        
      error ->
        error
    end
  end
  
  defp high_entropy?(data) do
    # Simple entropy check - count unique bytes
    bytes = :binary.bin_to_list(data)
    unique_count = bytes |> Enum.uniq() |> length()
    
    # High entropy if we have many unique bytes
    unique_count > byte_size(data) * 0.5
  end
  
  defp strip_header(<<"ENC1", rest::binary>>), do: {:ok, rest}
  defp strip_header(_), do: {:error, :invalid_encryption_header}
end