TaxBand = Struct.new(:name, :lower_pence, :rate, keyword_init: true) do
  def covers?(pence)
    pence >= lower_pence
  end
end

TAX_BANDS = [
  TaxBand.new(name: "basic", lower_pence: 0, rate: 0.20),
  TaxBand.new(name: "higher", lower_pence: 5_027_000, rate: 0.40)
].freeze
