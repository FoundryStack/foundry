defmodule IgamingRef.Cldr do
  @moduledoc """
  CLDR backend for ex_money / ash_money. Required for Money attribute types.
  """
  use Cldr,
    locales: ["en"],
    default_locale: "en",
    otp_app: :igaming_ref,
    providers: [Cldr.Number, Cldr.List, Cldr.Unit, Cldr.DateTime, Cldr.Calendar]
end
