defmodule FoundryWeb.EndpointConfigTest do
  use ExUnit.Case

  describe "check_origin configuration" do
    test "dev mode disables check_origin" do
      # In dev mode, check_origin should be false
      if Application.get_env(:foundry_web, FoundryWeb.Endpoint)[:check_origin] == false do
        assert true
      else
        config = Application.get_env(:foundry_web, FoundryWeb.Endpoint)
        IO.inspect(config, label: "Endpoint config in dev")
        assert false, "check_origin should be false in dev mode"
      end
    end

    test "endpoint url is configured with host and port" do
      url_config = Application.get_env(:foundry_web, FoundryWeb.Endpoint, []) |> Keyword.get(:url, [])
      assert url_config[:host] == "127.0.0.1"
      # Port will vary based on runtime selection
      assert is_integer(url_config[:port]) or url_config[:port] == nil
    end
  end
end
