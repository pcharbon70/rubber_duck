defmodule RubberDuck.Projects.SecurityValidatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Projects.SecurityValidator
  
  describe "validate_filename/2" do
    test "accepts safe filenames" do
      assert :ok = SecurityValidator.validate_filename("document.txt")
      assert :ok = SecurityValidator.validate_filename("image.png")
      assert :ok = SecurityValidator.validate_filename("code.ex")
      assert :ok = SecurityValidator.validate_filename("data.json")
    end
    
    test "rejects dangerous extensions by default" do
      assert {:error, {:dangerous_extension, ".exe"}} = 
        SecurityValidator.validate_filename("malware.exe")
      
      assert {:error, {:dangerous_extension, ".bat"}} = 
        SecurityValidator.validate_filename("script.bat")
      
      assert {:error, {:dangerous_extension, ".dll"}} = 
        SecurityValidator.validate_filename("library.dll")
    end
    
    test "allows dangerous extensions when explicitly permitted" do
      assert :ok = SecurityValidator.validate_filename("program.exe", allow_dangerous: true)
    end
    
    test "enforces allowed extensions when specified" do
      opts = [allowed_extensions: [".txt", ".md", ".pdf"]]
      
      assert :ok = SecurityValidator.validate_filename("doc.txt", opts)
      assert :ok = SecurityValidator.validate_filename("readme.md", opts)
      
      assert {:error, {:extension_not_allowed, ".jpg"}} = 
        SecurityValidator.validate_filename("image.jpg", opts)
    end
    
    test "detects path traversal attempts in filename" do
      assert {:error, :path_traversal_in_filename} = 
        SecurityValidator.validate_filename("../etc/passwd")
      
      assert {:error, :path_traversal_in_filename} = 
        SecurityValidator.validate_filename("..\\windows\\system32")
      
      assert {:error, :path_traversal_in_filename} = 
        SecurityValidator.validate_filename("file%2e%2e/secret")
    end
  end
  
  describe "validate_content_bytes/3" do
    test "accepts safe text content" do
      assert :ok = SecurityValidator.validate_content_bytes(
        "Hello, World!", "greeting.txt"
      )
      
      assert :ok = SecurityValidator.validate_content_bytes(
        """
        defmodule Example do
          def hello, do: "world"
        end
        """,
        "example.ex"
      )
    end
    
    test "detects script injection patterns" do
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "<script>alert('XSS')</script>",
          "page.html"
        )
      
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "Click <a href='javascript:void(0)'>here</a>",
          "link.html"
        )
    end
    
    test "detects SQL injection patterns" do
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "SELECT * FROM users; DROP TABLE users;",
          "query.sql"
        )
      
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "' OR 1=1 --",
          "input.txt"
        )
    end
    
    test "detects command injection patterns" do
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "echo $(rm -rf /)",
          "script.sh"
        )
      
      assert {:error, {:suspicious_content_pattern, _}} = 
        SecurityValidator.validate_content_bytes(
          "data; rm -rf /tmp/*",
          "command.txt"
        )
    end
    
    test "validates content size" do
      large_content = String.duplicate("a", 11 * 1024 * 1024)  # 11MB
      
      assert {:error, {:content_too_large, _, _}} = 
        SecurityValidator.validate_content_bytes(
          large_content, 
          "large.txt",
          max_content_size: 10 * 1024 * 1024
        )
    end
    
    test "validates archive formats" do
      # Valid ZIP header
      zip_header = <<0x50, 0x4B, 0x03, 0x04>> <> String.duplicate(<<0>>, 100)
      assert :ok = SecurityValidator.validate_content_bytes(zip_header, "archive.zip")
      
      # Invalid archive content
      assert {:error, {:invalid_archive_format, ".zip"}} = 
        SecurityValidator.validate_content_bytes("not a zip file", "fake.zip")
    end
    
    test "skips pattern validation for binary files" do
      # Binary content with null bytes
      binary_content = <<0, 1, 2, 3, 0, 255, 254, 253>>
      
      # Should not trigger pattern validation for binary files
      assert :ok = SecurityValidator.validate_content_bytes(
        binary_content <> "; DROP TABLE users;",
        "data.bin"
      )
    end
  end
  
  describe "get_content_type/1" do
    setup do
      temp_dir = Path.join(System.tmp_dir!(), "security_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(temp_dir)
      
      on_exit(fn -> File.rm_rf!(temp_dir) end)
      
      %{temp_dir: temp_dir}
    end
    
    test "detects image types", %{temp_dir: temp_dir} do
      # PNG
      png_path = Path.join(temp_dir, "image.png")
      File.write!(png_path, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "rest">>)
      assert {:ok, "image/png"} = SecurityValidator.get_content_type(png_path)
      
      # JPEG
      jpeg_path = Path.join(temp_dir, "image.jpg")
      File.write!(jpeg_path, <<0xFF, 0xD8, 0xFF, "rest">>)
      assert {:ok, "image/jpeg"} = SecurityValidator.get_content_type(jpeg_path)
      
      # GIF
      gif_path = Path.join(temp_dir, "image.gif")
      File.write!(gif_path, "GIF89a" <> "rest")
      assert {:ok, "image/gif"} = SecurityValidator.get_content_type(gif_path)
    end
    
    test "detects document types", %{temp_dir: temp_dir} do
      # PDF
      pdf_path = Path.join(temp_dir, "document.pdf")
      File.write!(pdf_path, "%PDF-1.4\n%rest")
      assert {:ok, "application/pdf"} = SecurityValidator.get_content_type(pdf_path)
    end
    
    test "detects text types", %{temp_dir: temp_dir} do
      # HTML
      html_path = Path.join(temp_dir, "page.html")
      File.write!(html_path, "<!DOCTYPE html><html>")
      assert {:ok, "text/html"} = SecurityValidator.get_content_type(html_path)
      
      # JSON
      json_path = Path.join(temp_dir, "data.json")
      File.write!(json_path, "{\"key\": \"value\"}")
      assert {:ok, "application/json"} = SecurityValidator.get_content_type(json_path)
      
      # Plain text
      txt_path = Path.join(temp_dir, "readme.txt")
      File.write!(txt_path, "This is plain text")
      assert {:ok, "text/plain"} = SecurityValidator.get_content_type(txt_path)
    end
    
    test "detects compressed types", %{temp_dir: temp_dir} do
      # GZIP
      gz_path = Path.join(temp_dir, "archive.gz")
      File.write!(gz_path, <<0x1F, 0x8B, "rest">>)
      assert {:ok, "application/gzip"} = SecurityValidator.get_content_type(gz_path)
    end
  end
end