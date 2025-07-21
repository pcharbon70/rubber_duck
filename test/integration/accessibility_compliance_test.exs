defmodule RubberDuckWeb.Integration.AccessibilityComplianceTest do
  @moduledoc """
  Integration tests for accessibility compliance.
  
  Tests WCAG 2.1 AA compliance, ARIA implementation,
  screen reader support, and inclusive design patterns.
  """
  
  use RubberDuckWeb.ConnCase
  
  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  
  @moduletag :integration
  
  setup do
    user = user_fixture()
    project = %{
      id: "a11y-test-#{System.unique_integer()}",
      name: "Accessibility Test Project"
    }
    
    %{user: user, project: project}
  end
  
  describe "ARIA landmarks and regions" do
    test "provides proper landmark structure", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Main landmarks
      assert html =~ ~r/<header[^>]*role="banner"/
      assert html =~ ~r/<nav[^>]*role="navigation"/
      assert html =~ ~r/<main[^>]*role="main"/
      assert html =~ ~r/<aside[^>]*role="complementary"/
      
      # Labeled regions
      assert html =~ ~r/aria-label="File explorer"/
      assert html =~ ~r/aria-label="Code editor"/
      assert html =~ ~r/aria-label="AI Assistant chat"/
      assert html =~ ~r/aria-label="Status bar"/
    end
    
    test "uses semantic HTML elements", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Semantic structure
      assert html =~ "<header"
      assert html =~ "<nav"
      assert html =~ "<main"
      assert html =~ "<section"
      assert html =~ "<article"
      assert html =~ "<aside"
      assert html =~ "<footer"
      
      # Proper heading hierarchy
      assert html =~ "<h1"
      assert Regex.scan(~r/<h1[^>]*>/, html) |> length() == 1  # Only one h1
      
      # Check heading order
      headings = Regex.scan(~r/<h(\d)[^>]*>/, html)
      heading_levels = Enum.map(headings, fn [_, level] -> String.to_integer(level) end)
      
      # No skipped levels
      for i <- 0..(length(heading_levels) - 2) do
        current = Enum.at(heading_levels, i)
        next = Enum.at(heading_levels, i + 1)
        assert next <= current + 1
      end
    end
  end
  
  describe "keyboard accessibility" do
    test "all interactive elements are keyboard accessible", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Find all interactive elements
      interactive_elements = [
        "button",
        "a[href]",
        "input",
        "textarea",
        "select",
        "[tabindex]"
      ]
      
      for selector <- interactive_elements do
        elements = Regex.scan(~r/<#{selector}[^>]*>/, html)
        
        for element <- elements do
          # Should have tabindex if needed
          if selector == "[tabindex]" do
            assert element =~ ~r/tabindex="0"|tabindex="-1"/
          end
          
          # Should not have positive tabindex
          refute element =~ ~r/tabindex="[1-9]/
        end
      end
    end
    
    test "focus management and indicators", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Tab through interface
      view
      |> element("body")
      |> render_keydown(%{"key" => "Tab"})
      
      html = render(view)
      # Should have visible focus indicator
      assert html =~ "focus:ring" or html =~ "focus-visible"
      
      # Focus trap in modals
      view
      |> element("button[phx-click=\"open_settings\"]")
      |> render_click()
      
      # Tab should cycle within modal
      for _ <- 1..10 do
        view
        |> element(".modal")
        |> render_keydown(%{"key" => "Tab"})
      end
      
      assert view.assigns.focus_trapped == true
      assert view.assigns.focus_area == "modal"
    end
    
    test "escape key behavior", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Open modal
      view
      |> element("button[phx-click=\"open_settings\"]")
      |> render_click()
      
      assert render(view) =~ "settings-modal"
      
      # Escape closes modal
      view
      |> element(".modal")
      |> render_keydown(%{"key" => "Escape"})
      
      refute render(view) =~ "settings-modal"
      
      # Focus returns to trigger element
      assert view.assigns.focus_return_to == "settings-button"
    end
  end
  
  describe "screen reader support" do
    test "provides appropriate ARIA labels", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Buttons with icons should have labels
      icon_buttons = Regex.scan(~r/<button[^>]*class="[^"]*icon[^"]*"[^>]*>/, html)
      
      for button <- icon_buttons do
        assert button =~ ~r/aria-label="[^"]+"|title="[^"]+"/
      end
      
      # Form inputs should have labels
      inputs = Regex.scan(~r/<input[^>]*>/, html)
      
      for input <- inputs do
        if input =~ ~r/type="(?!hidden)/ do
          assert input =~ ~r/aria-label=|aria-labelledby=|id=/
        end
      end
    end
    
    test "live regions for dynamic content", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Status messages region
      assert html =~ ~r/aria-live="polite"/
      assert html =~ ~r/role="status"/
      
      # Chat messages region
      assert html =~ ~r/aria-live="polite".*role="log"/
      
      # Send a message to test announcement
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Test message"})
      |> render_submit()
      
      :timer.sleep(50)
      
      html = render(view)
      # New message in live region
      assert html =~ ~r/<div[^>]*aria-live[^>]*>.*Test message/s
    end
    
    test "error announcements", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Trigger an error
      send(view.pid, {:error, "File not found"})
      :timer.sleep(50)
      
      html = render(view)
      # Error in alert region
      assert html =~ ~r/role="alert"/
      assert html =~ "File not found"
      
      # Associated with form field errors
      view
      |> form("form[phx-submit=\"save_file\"]", %{filename: ""})
      |> render_submit()
      
      html = render(view)
      assert html =~ ~r/aria-invalid="true"/
      assert html =~ ~r/aria-describedby="[^"]*error"/
    end
  end
  
  describe "color contrast and visual design" do
    test "sufficient color contrast ratios", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Check CSS classes for contrast compliance
      # These should be validated with actual color values
      contrast_classes = [
        "text-gray-900",      # Dark text on light
        "bg-white",           # Light backgrounds
        "text-white",         # Light text on dark
        "bg-gray-900"         # Dark backgrounds
      ]
      
      for class <- contrast_classes do
        assert html =~ class
      end
      
      # Error and success states should not rely on color alone
      assert html =~ ~r/class="[^"]*error[^"]*"[^>]*>.*(?:Error|Failed|Invalid)/
      assert html =~ ~r/class="[^"]*success[^"]*"[^>]*>.*(?:Success|Complete|Valid)/
    end
    
    test "focus indicators meet contrast requirements", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Focus styles should be defined
      assert html =~ "focus:ring-2" or html =~ "focus:outline"
      assert html =~ "focus:ring-blue-500" or html =~ "focus:border-blue-500"
      
      # Dark mode support
      assert html =~ "dark:focus:ring-blue-400"
    end
  end
  
  describe "responsive and zoom support" do
    test "supports 200% zoom without horizontal scroll", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"zoom" => 2.0})
      
      # Layout should adapt
      assert view.assigns.zoom_level == 2.0
      assert view.assigns.layout_mode == "stacked"  # Single column at high zoom
      
      html = render(view)
      # Responsive classes
      assert html =~ "sm:hidden" or html =~ "lg:block"
      assert html =~ "overflow-x-auto"
    end
    
    test "text remains readable when resized", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # No fixed pixel font sizes for body text
      refute html =~ ~r/font-size:\s*\d+px/
      
      # Using relative units
      assert html =~ "text-sm" or html =~ "text-base" or html =~ "text-lg"
      assert html =~ "rem" or html =~ "em"
    end
  end
  
  describe "form accessibility" do
    test "form validation and error handling", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Submit invalid form
      view
      |> form("form[phx-submit=\"create_file\"]", %{filename: "", content: ""})
      |> render_submit()
      
      html = render(view)
      
      # Error summary
      assert html =~ ~r/role="alert"/
      assert html =~ "Please fix the following errors"
      
      # Field-level errors
      assert html =~ ~r/<input[^>]*aria-invalid="true"/
      assert html =~ ~r/<span[^>]*id="filename-error"/
      assert html =~ "Filename is required"
      
      # Error association
      assert html =~ ~r/aria-describedby="filename-error"/
    end
    
    test "form field grouping and instructions", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Fieldsets for related inputs
      assert html =~ ~r/<fieldset[^>]*>.*<legend[^>]*>.*Settings/s
      
      # Help text association
      assert html =~ ~r/<input[^>]*aria-describedby="[^"]*help"/
      assert html =~ ~r/<span[^>]*id="[^"]*help"[^>]*>.*Format:/
      
      # Required field indicators
      assert html =~ ~r/<label[^>]*>.*\*.*<\/label>/
      assert html =~ ~r/aria-required="true"/
    end
  end
  
  describe "alternative text and media" do
    test "images have appropriate alt text", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # All images should have alt attribute
      images = Regex.scan(~r/<img[^>]*>/, html)
      
      for img <- images do
        assert img =~ ~r/alt="/
        
        # Decorative images should have empty alt
        if img =~ ~r/decorative|icon/ do
          assert img =~ ~r/alt=""/
        else
          # Meaningful images should have descriptive alt
          assert img =~ ~r/alt="[^"]+"/
        end
      end
    end
    
    test "icons have text alternatives", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # SVG icons
      svg_icons = Regex.scan(~r/<svg[^>]*>.*?<\/svg>/s, html)
      
      for svg <- svg_icons do
        # Should have title or aria-label
        assert svg =~ ~r/<title>|aria-label="|role="img"/
      end
      
      # Icon fonts
      icon_elements = Regex.scan(~r/<[^>]*class="[^"]*icon[^"]*"[^>]*>/, html)
      
      for element <- icon_elements do
        # Should have screen reader text or aria-label
        assert element =~ ~r/aria-label="|<span[^>]*class="[^"]*sr-only/
      end
    end
  end
  
  describe "timing and motion" do
    test "provides controls for auto-updating content", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Auto-save indicator
      assert html =~ "Auto-save" or html =~ "Saving automatically"
      
      # Should have pause control
      assert has_element?(view, "button[aria-label*=pause]") or
             has_element?(view, "button[aria-label*=stop]")
      
      # Check for reduced motion support
      assert html =~ "prefers-reduced-motion" or
             html =~ "motion-reduce"
    end
    
    test "respects prefers-reduced-motion", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"prefers_reduced_motion" => true})
      
      # Animations should be disabled
      assert view.assigns.animations_enabled == false
      
      html = render(view)
      # CSS classes for reduced motion
      assert html =~ "motion-safe:" or html =~ "motion-reduce:"
      
      # No auto-playing animations
      refute html =~ "animate-pulse" or html =~ "animate-spin"
    end
  end
  
  describe "language and readability" do
    test "specifies page language", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # HTML lang attribute
      assert html =~ ~r/<html[^>]*lang="en"/
      
      # Language changes for code blocks
      code_blocks = Regex.scan(~r/<code[^>]*>/, html)
      for block <- code_blocks do
        if block =~ "language-" do
          assert block =~ ~r/lang="[^"]+"/
        end
      end
    end
    
    test "uses clear and simple language", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # Avoid jargon in UI labels
      refute html =~ ~r/>(?:regex|regexp)</i  # Use "pattern" instead
      refute html =~ ~r/>(?:params|args)</i    # Use "settings" or "options"
      
      # Clear action labels
      assert html =~ "Save" or html =~ "Cancel" or html =~ "Delete"
      refute html =~ ~r/>\?<\/button>/  # No mystery meat navigation
    end
  end
  
  describe "assistive technology compatibility" do
    test "works with screen reader modes", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session",
        connect_params: %{"screen_reader" => true})
      
      # Enhanced descriptions for screen readers
      assert view.assigns.screen_reader_mode == true
      
      html = render(view)
      # Additional context for screen readers
      assert html =~ "sr-only"  # Screen reader only text
      assert html =~ ~r/aria-label="[^"]{10,}"/  # Detailed labels
      
      # Simplified layout option
      assert has_element?(view, "button", "Simplified view")
    end
    
    test "table accessibility", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/session")
      
      # If tables are present
      if html =~ "<table" do
        # Proper table structure
        assert html =~ ~r/<table[^>]*>.*<caption/s or
               html =~ ~r/<table[^>]*aria-label="/
        
        # Column headers
        assert html =~ "<thead"
        assert html =~ ~r/<th[^>]*scope="col"/
        
        # Row headers if applicable
        if html =~ ~r/<th[^>]*scope="row"/ do
          assert html =~ ~r/id="[^"]+"/  # Headers should have IDs
        end
      end
    end
  end
end