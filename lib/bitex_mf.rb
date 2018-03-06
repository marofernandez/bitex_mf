#require 'json'
require 'bitex'
require 'bitstamp'
require 'cexio'

class Bitex_MF
  def self.Ticker

  	cex_api = CEX::API.new('','','')

  	ciclos = 3600
  	bid_spread_max = 2
  	ask_spread_max = 0
  	while (ciclos > 0)

  		# Comisiones
  		# BITEX 0,5%
  		# BITSTAMP 0,25%
  		# CEXIO 0,25%

    	bitex_ticker = Bitex::BitcoinMarketData.ticker
  		bitstamp_ticker = Bitstamp.ticker
  		cexio_ticker = cex_api.ticker('BTC/USD')
#  		puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
#  		puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
#  		puts "CEXio Ticker: #{cexio_ticker["last"]}. bid: #{cexio_ticker["bid"]} - ask: #{cexio_ticker["ask"]}"

		# BIDs
		if (bitstamp_ticker.bid.to_f > cexio_ticker["bid"]) then
			bid_high = bitstamp_ticker.bid.to_f
			bid_exchange = "bitstamp"
		else
			bid_high = cexio_ticker["bid"]
			bid_exchange = "cexio"
		end
		bid_spread = bitex_ticker[:bid] / bid_high
  		if bid_spread < 0.9925 then
#  			puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
#  			puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
  			puts " >>> Comprar en BITEX a #{bitex_ticker[:bid]} y vender en #{bid_exchange} a #{bid_high}. Spread: #{bid_spread}"
  		else
  			puts "BID spread not enough: #{bid_spread}"
  		end

  		if bid_spread < bid_spread_max then
  			bid_spread_max = bid_spread
  			bid_exchange_max = bid_exchange
  		end

  		#ASKs
=begin
  		ask_spread = bitex_ticker[:ask] / bitstamp_ticker.ask.to_f


  		if ask_spread > 1.0076 then
#  			puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
#  			puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
  			puts " >>> Vender en BITEX a #{bitex_ticker[:ask]} y comprar en BITSTAMP a #{bitstamp_ticker.ask}"
  		else
  			puts "ASK spread not enough: #{ask_spread}"
  		end
  		if ask_spread < ask_spread_max then
  			ask_spread_max = ask_spread_max
  		end
=end

  		sleep 1
  		puts ""
  		ciclos = ciclos - 1
  	end
  	puts "MAX_BID: #{bid_spread_max} @ #{bid_exchange_max}"
#  	puts "MAX_ASK: #{ask_spread_max}"

  end

  def self.OrderBook
  	puts Bitex::BitcoinMarketData.order_book
  end
end
