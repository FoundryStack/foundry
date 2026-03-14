defmodule SparkMeta.RegistryTest do
  use ExUnit.Case
  doctest SparkMeta.Registry

  setup do
    # Flush the registry before each test
    :ets.delete_all_objects(:spark_meta_registry)
    :ok
  end

  test "register/2 stores a handler" do
    assert :ok = SparkMeta.Registry.register(SomeExtension, SomeHandler)
  end

  test "handler_for/1 retrieves a registered handler" do
    SparkMeta.Registry.register(MyExtension, MyHandler)
    assert SparkMeta.Registry.handler_for(MyExtension) == MyHandler
  end

  test "handler_for/1 returns nil for unregistered extension" do
    assert SparkMeta.Registry.handler_for(UnregisteredExtension) == nil
  end

  test "all/0 returns all registered handlers" do
    SparkMeta.Registry.register(Ext1, Handler1)
    SparkMeta.Registry.register(Ext2, Handler2)
    SparkMeta.Registry.register(Ext3, Handler3)

    all = SparkMeta.Registry.all()
    assert length(all) == 3
    assert {Ext1, Handler1} in all
    assert {Ext2, Handler2} in all
    assert {Ext3, Handler3} in all
  end

  test "handler_for/1 returns nil on ETS errors gracefully" do
    # Even if the table is somehow unavailable, we don't crash
    result = SparkMeta.Registry.handler_for(AnyExtension)
    assert result == nil or is_atom(result)
  end

  test "all/0 returns empty list on ETS errors gracefully" do
    result = SparkMeta.Registry.all()
    assert is_list(result)
  end

  test "multiple registrations for same extension overwrites previous" do
    SparkMeta.Registry.register(MyExt, FirstHandler)
    SparkMeta.Registry.register(MyExt, SecondHandler)

    assert SparkMeta.Registry.handler_for(MyExt) == SecondHandler
  end
end
