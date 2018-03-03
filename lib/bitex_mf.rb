require 'bitex'

class Bitex_MF
  def self.Ticker
    puts Bitex::BitcoinMarketData.ticker
  end

  def self.OrderBook
  	puts Bitex::BitcoinMarketData.order_book
  end
end
