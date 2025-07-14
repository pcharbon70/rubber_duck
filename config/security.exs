# Security configuration for RubberDuck Instructions system

import Config

config :rubber_duck, :security,
  # Global security settings
  enabled: true,
  default_security_level: :balanced,
  
  # Template processing limits
  max_template_size: 10_000,  # 10KB
  max_processing_time: 5_000,  # 5 seconds
  
  # Rate limiting configuration
  rate_limits: %{
    # Per-user limits
    user: {10, :minute},
    # Per-template limits
    template: {20, :minute}, 
    # Global system limits
    global: {100, :minute}
  },
  
  # Rate limiting adjustment factors
  adaptive_factors: %{
    suspicious: 0.2,   # 20% of normal limit
    elevated: 0.5,     # 50% of normal limit
    normal: 1.0,       # 100% of normal limit
    trusted: 2.0       # 200% of normal limit
  },
  
  # Sandbox execution settings
  sandbox: %{
    timeout: 5_000,         # 5 seconds
    max_heap_size: 50_000_000,  # 50MB in words
    default_security_level: :balanced
  },
  
  # Security validation settings
  validation: %{
    # Enable/disable specific validations
    injection_detection: true,
    xss_protection: true,
    path_traversal_protection: true,
    code_execution_protection: true,
    
    # Security patterns to detect
    dangerous_patterns: [
      # System commands
      ~r/System\.cmd/i,
      ~r/Process\.spawn/i,
      ~r/:os\.cmd/i,
      
      # Code evaluation
      ~r/Code\.eval/i,
      ~r/Kernel\.eval/i,
      ~r/String\.to_atom/i,
      
      # File system access
      ~r/File\./i,
      ~r/Path\./i,
      ~r/IO\./i,
      
      # Network access
      ~r/HTTPoison/i,
      ~r/Req\./i,
      ~r/GenServer\.call/i,
      
      # Database access
      ~r/Ecto\./i,
      ~r/Repo\./i,
      
      # Process manipulation
      ~r/Process\./i,
      ~r/GenServer\./i,
      ~r/Agent\./i,
      ~r/Task\./i
    ],
    
    # XSS patterns
    xss_patterns: [
      ~r/<script[^>]*>.*?<\/script>/i,
      ~r/javascript:/i,
      ~r/on\w+\s*=/i,
      ~r/expression\s*\(/i
    ],
    
    # Path traversal patterns
    path_traversal_patterns: [
      ~r/\.\./,
      ~r/\/etc\//i,
      ~r/\/var\//i,
      ~r/\/tmp\//i,
      ~r/\/proc\//i,
      ~r/\/sys\//i
    ]
  },
  
  # Security monitoring settings
  monitoring: %{
    # Event windows for threat detection
    window_size: 3600,  # 1 hour in seconds
    cleanup_interval: 300_000,  # 5 minutes
    
    # Threat scoring weights
    threat_weights: %{
      injection_attempt: 10,
      rate_limit_exceeded: 3,
      sandbox_violation: 8,
      resource_limit_exceeded: 5,
      template_processed: -1,  # Good behavior reduces threat score
      anomaly_detected: 5
    },
    
    # Threat levels
    threat_levels: %{
      low: 0..10,
      medium: 11..30,
      high: 31..50,
      critical: 51..100,
      blocked: 101..999999
    },
    
    # Alert thresholds
    alert_thresholds: %{
      injection_threshold: 3,
      anomaly_sensitivity: :medium,
      alert_cooldown: 300  # 5 minutes
    }
  },
  
  # Audit logging settings
  audit: %{
    # Event types to log
    logged_events: [
      :template_processed,
      :security_violation,
      :injection_attempt,
      :rate_limit_exceeded,
      :sandbox_violation,
      :resource_limit_exceeded,
      :user_blocked,
      :anomaly_detected
    ],
    
    # Log retention
    retention_days: 30,
    
    # Cleanup frequency
    cleanup_frequency: 86400  # 24 hours in seconds
  },
  
  # Security levels configuration
  security_levels: %{
    strict: %{
      # Minimal allowed functions
      allowed_functions: [
        "upcase", "downcase", "trim", "length", "join", "count"
      ],
      
      # Stricter validation
      max_template_size: 1_000,  # 1KB
      max_processing_time: 1_000,  # 1 second
      
      # Reduced rate limits
      rate_limit_factor: 0.5
    },
    
    balanced: %{
      # Standard functions
      allowed_functions: [
        "upcase", "downcase", "trim", "length", "join", "count",
        "capitalize", "split", "first", "last", "size",
        "append", "prepend", "remove", "truncate", "strip"
      ],
      
      # Standard validation
      max_template_size: 10_000,  # 10KB
      max_processing_time: 5_000,  # 5 seconds
      
      # Normal rate limits
      rate_limit_factor: 1.0
    },
    
    relaxed: %{
      # Extended functions
      allowed_functions: [
        "upcase", "downcase", "trim", "length", "join", "count",
        "capitalize", "reverse", "split", "replace", "slice",
        "contains", "starts_with", "ends_with", "to_integer", "to_string",
        "abs", "min", "max", "first", "last", "size",
        "append", "prepend", "remove", "truncate", "strip",
        "plus", "minus", "times", "divided_by", "modulo"
      ],
      
      # Relaxed validation
      max_template_size: 50_000,  # 50KB
      max_processing_time: 10_000,  # 10 seconds
      
      # Increased rate limits
      rate_limit_factor: 2.0
    }
  }

# Environment-specific security settings
if config_env() == :test do
  config :rubber_duck, :security,
    # More permissive settings for testing
    rate_limits: %{
      user: {100, :minute},
      template: {200, :minute},
      global: {1000, :minute}
    },
    
    # Faster cleanup for tests
    monitoring: %{
      window_size: 300,  # 5 minutes
      cleanup_interval: 30_000,  # 30 seconds
      
      threat_weights: %{
        injection_attempt: 10,
        rate_limit_exceeded: 3,
        sandbox_violation: 8,
        resource_limit_exceeded: 5,
        template_processed: -1,
        anomaly_detected: 5
      },
      
      threat_levels: %{
        low: 0..10,
        medium: 11..30,
        high: 31..50,
        critical: 51..100,
        blocked: 101..999999
      },
      
      alert_thresholds: %{
        injection_threshold: 3,
        anomaly_sensitivity: :medium,
        alert_cooldown: 60  # 1 minute
      }
    },
    
    audit: %{
      logged_events: [
        :template_processed,
        :security_violation,
        :injection_attempt,
        :rate_limit_exceeded,
        :sandbox_violation,
        :resource_limit_exceeded,
        :user_blocked,
        :anomaly_detected
      ],
      retention_days: 7,
      cleanup_frequency: 3600  # 1 hour
    }
end

if config_env() == :prod do
  config :rubber_duck, :security,
    # Stricter production settings
    default_security_level: :strict,
    
    # Tighter rate limits
    rate_limits: %{
      user: {5, :minute},
      template: {10, :minute},
      global: {50, :minute}
    },
    
    # Enhanced monitoring
    monitoring: %{
      window_size: 7200,  # 2 hours
      cleanup_interval: 600_000,  # 10 minutes
      
      threat_weights: %{
        injection_attempt: 15,  # Higher weight in production
        rate_limit_exceeded: 5,
        sandbox_violation: 12,
        resource_limit_exceeded: 8,
        template_processed: -1,
        anomaly_detected: 8
      },
      
      threat_levels: %{
        low: 0..5,
        medium: 6..15,
        high: 16..30,
        critical: 31..50,
        blocked: 51..999999
      },
      
      alert_thresholds: %{
        injection_threshold: 2,  # More sensitive
        anomaly_sensitivity: :high,
        alert_cooldown: 600  # 10 minutes
      }
    },
    
    audit: %{
      logged_events: [
        :template_processed,
        :security_violation,
        :injection_attempt,
        :rate_limit_exceeded,
        :sandbox_violation,
        :resource_limit_exceeded,
        :user_blocked,
        :anomaly_detected
      ],
      retention_days: 90,  # Longer retention
      cleanup_frequency: 43200  # 12 hours
    }
end