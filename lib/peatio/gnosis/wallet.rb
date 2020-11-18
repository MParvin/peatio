module Gnosis
  class Wallet < Peatio::Wallet::Abstract

    # TODO: Add ability to use Gnosis smart contracts
    def initialize(custom_features = {})
      @features = custom_features.slice(*SUPPORTED_FEATURES)
      @settings = {}
    end

    def configure(settings = {})
      # Clean client state during configure.
      @client = nil

      @settings.merge!(settings.slice(*SUPPORTED_SETTINGS))

      @wallet = @settings.fetch(:wallet) do
        raise Peatio::Wallet::MissingSettingError, :wallet
      end.slice(:uri, :address, :secret)

      @currency = @settings.fetch(:currency) do
        raise Peatio::Wallet::MissingSettingError, :currency
      end.slice(:id, :base_factor, :options)
    end

    # For now we will use eth load_balance from eth plugin (it will require to set uri node in wallet settings)
    def load_balance!
      if @currency.dig(:options, :erc20_contract_address).present?
        load_erc20_balance(@wallet.fetch(:address))
      else
        client.json_rpc(:eth_getBalance, [normalize_address(@wallet.fetch(:address)), 'latest'])
        .hex
        .to_d
        .yield_self { |amount| convert_from_base_unit(amount) }
      end
    rescue Ethereum::Client::Error => e
      raise Peatio::Wallet::ClientError, e
    end

    private

    def load_erc20_balance(address)
      data = abi_encode('balanceOf(address)', normalize_address(address))
      client.json_rpc(:eth_call, [{ to: contract_address, data: data }, 'latest'])
        .hex
        .to_d
        .yield_self { |amount| convert_from_base_unit(amount) }
    end

    def client
      uri = @wallet.fetch(:uri) { raise Peatio::Wallet::MissingSettingError, :uri }
      @client ||= Client.new(uri, idle_timeout: 1)
    end

    def contract_address
      normalize_address(@currency.dig(:options, :erc20_contract_address))
    end

    def normalize_address(address)
      address.downcase
    end

    def abi_encode(method, *args)
      '0x' + args.each_with_object(Digest::SHA3.hexdigest(method, 256)[0...8]) do |arg, data|
        data.concat(arg.gsub(/\A0x/, '').rjust(64, '0'))
      end
    end

    def convert_from_base_unit(value)
      value.to_d / @currency.fetch(:base_factor)
    end
  end
end
