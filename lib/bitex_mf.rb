#require 'json'
require 'bitex'
require 'bitstamp'
require 'cexio'

=begin
Asumiendo compra en Bitex (el ask mas bajo) y venta en CEXio (el bid mas alto), o que tienen suficiente spread

-Busqueda de balances:
  En Bitex deberiamos tener mas de $50
  En CEXio deberiamos tener mas bitcoins que los que puedo comprar con $50 en Bitex, asumamos 0,005

-Ejecutar ordenes en ambos exchanges
  En Bitex compro todo lo que pueda de BTC con $50, Bitex me cobra 0,5% de transaccion
    BTC = $50 / BITEX_ASK * (1-0,005) => asumamos un ask de $10.000 = 0,004975
  En CEXio vendo la cantidad de bitcoins que recibi en Bitex, CEXio me cobra 0,25% de transaccion
    USD = 0,004975 * CEXIO_BID * (1-0,0025) => asumamos un bid de $10.200 = $50,61(81375)

-Armar la orden en Bitex para recuperar los dolares en caso que suba el bitcoin
  En Bitex quiero vender ganando un 1% en bitcoins, Bitex me cobra 0,5% de transaccion
    ASK = (50 / (1-0,005)) / (0,004975 * (1-0,01)) => vendemos 0,00492525 bitcoins a $10202,78(29)
-Armar la orden en CEXio para recuperar los bitcoins en caso que baje el bitcoin
  En CEXio quiero comprar ganando un 1% en bitcoins, CEXio me cobra 0,16% de transaccion
    BID = (50,61 * (1-0,0016)) / (0,004975 * (1+0,01)) => compramos 0,00502475 a $10.056.0(275)

-Dormir por 60 min
=end

class Bitex_MF
  
  def self.RunWhenSpreadBiggerThan(target_spread = 0.01)
    cex_api = CEX::API.new('','','')
    cexio_commission_taker = 0.0025
    bitex_commission = 0.005
    usd_to_invest = 50

    ciclos = 3600 * 6
    while (ciclos > 0)
      bitex_ticker = Bitex::BitcoinMarketData.ticker
      cexio_ticker = cex_api.ticker('BTC/USD')
      bitex_cexio_spread = 1 - (bitex_ticker[:ask] / cexio_ticker["bid"])
      spread_with_fees = bitex_cexio_spread - (bitex_commission + cexio_commission_taker)
      cexio_bitex_spread = 1 - (cexio_ticker["ask"] / bitex_ticker[:bid])
      spread_with_fees_rev = cexio_bitex_spread - (bitex_commission + cexio_commission_taker)
      if ((ciclos % 30) == 0) then
        puts "[DEBUG]: Checkpoint: #{ciclos}"
        puts "[DEBUG]: BUY in Bitex @ #{bitex_ticker[:ask].round(2)} and SELL in CEXio @ #{cexio_ticker["bid"].round(2)} - SPREAD: #{bitex_cexio_spread.round(5)} (#{spread_with_fees.round(5)})"
        puts "[DEBUG]: BUY in CEXio @ #{cexio_ticker["ask"].round(2)} and SELL in Bitex @ #{bitex_ticker[:bid].round(2)} - SPREAD: #{cexio_bitex_spread.round(5)} (#{spread_with_fees_rev.round(5)})"
      end
      if (spread_with_fees > target_spread) then
        puts "[DEBUG]: RunOnce:..."
        puts "[DEBUG]: Checkpoint: #{ciclos}"
        puts "[INFO]: BUY in Bitex @ #{bitex_ticker[:ask].round(2)} and SELL in CEXio @ #{cexio_ticker["bid"].round(2)} - SPREAD: #{bitex_cexio_spread.round(5)} (#{spread_with_fees.round(5)})"
        self.RunOnce(usd_to_invest, bitex_ticker[:ask])
        puts "[DEBUG]: Waiting 15 min..."
        sleep 899
      elsif (spread_with_fees_rev > target_spread) then
        puts "[DEBUG]: RunOnceRev:..."
        puts "[DEBUG]: Checkpoint: #{ciclos}"
        puts "[DEBUG]: BUY in CEXio @ #{cexio_ticker["ask"].round(2)} and SELL in Bitex @ #{bitex_ticker[:bid].round(2)} - SPREAD: #{cexio_bitex_spread.round(5)} (#{spread_with_fees_rev.round(5)})"
        self.RunOnceRev(usd_to_invest, cexio_ticker["ask"])
        puts "[DEBUG]: Waiting 15 min..."
        sleep 899
      end
      sleep 1
      ciclos = ciclos - 1
    end
    puts "[DEBUG]: We went for 6 hours straihgt... time to go home."
  end

  def self.RunOnce(usd_to_invest = 50, bitex_ticker_ask = 100)
    usd_available_bitex = self.GetUSDAvailableBitex
    puts "[INFO]: usd_available_bitex = #{usd_available_bitex}"
    if (usd_available_bitex > usd_to_invest) then
        btc_available_cexio = self.GetBTCAvailableCEXio
        puts "[INFO]: btc_available_cexio = #{btc_available_cexio}"
        if (btc_available_cexio > (usd_to_invest / bitex_ticker_ask)) then
          received_btc = self.MakeTransactionBitex(usd_to_invest)
          puts "[INFO]: received_btc = #{received_btc}"
          usd_collected = self.MakeTransactionCEXio(received_btc)
          puts "[INFO]: usd_collected = #{usd_collected}"
        else
          puts "[INFO]: No hay BTC suficientes para operar en CEXio"
        end
    else
      puts "[INFO]: No hay USD suficientes para operar en Bitex"
    end
  end

  def self.RunOnceRev(usd_to_invest = 50, cexio_ticker_ask = 100)
    usd_available_cexio = self.GetUSDAvailableCEXio
    puts "[INFO]: usd_available_cexio = #{usd_available_cexio}"
    usd_available_cexio = 51
    if (usd_available_cexio > usd_to_invest) then
        btc_available_bitex = self.GetBTCAvailableBitex
        puts "[INFO]: btc_available_bitex = #{btc_available_bitex}"
        if (btc_available_bitex > (usd_to_invest / cexio_ticker_ask)) then
          received_btc = self.MakeTransactionCEXioRev(usd_to_invest, cexio_ticker_ask)
          puts "[INFO]: received_btc = #{received_btc}"
          if (received_btc > 0) then
            usd_collected = self.MakeTransactionBitexRev(received_btc)
            puts "[INFO]: usd_collected = #{usd_collected}"
          end
        else
          puts "[INFO]: No hay BTC suficientes para operar en Bitex"
        end
    else
      puts "[INFO]: No hay USD suficientes para operar en CEXio"
    end
  end

  def self.MakeTransactionCEXio(btc_to_sell = 0)
    api_test_flag = 0

    btc_available_cexio = self.GetBTCAvailableCEXio
    puts "[DEBUG]: btc_available_cexio = #{btc_available_cexio}"

    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    cexio_commission_taker = 0.0025
    cexio_commission_maker = 0.0016
    margin_to_win = 0.02 # 2%

    if (btc_available_cexio > btc_to_sell) then
#      puts "Colocamos la orden de venta en CEXio"
      cexio_ticker = cex_api.ticker('BTC/USD')
#      puts cexio_ticker
      puts "[DEBUG]: El BID en CEXio es: #{cexio_ticker["bid"]}"
      price_to_ask = cexio_ticker["bid"]
#      puts "El precio a pedir: #{price_to_ask}"
      if ((api_test_flag == 1) && (btc_to_sell == 0)) then
        btc_to_sell = 0.005
      end
      usd_to_receive = btc_to_sell * price_to_ask * (1 - cexio_commission_taker)
      puts "[DEBUG]: Los USD a recibir serian: #{usd_to_receive}"
      if (api_test_flag == 1) then
        price_to_ask = 35000
        puts "[DEBUG]: Ponemos la orden pidiendo USD 35.000 (tope de CEXio)"
      end
      order_result = cex_api.place_order('sell', btc_to_sell, price_to_ask, 'BTC/USD')
      puts "[DEBUG]: Orden en CEXio #{order_result}"
#      puts "Order ID: #{order_result["id"]}"
#      puts "Order Complete: #{order_result["complete"]}"
#      puts "Order Price: #{order_result["price"]}"
#      puts "Order Amount: #{order_result["amount"]}"
#      puts "Order Pending: #{order_result["pending"]}"
      if !(order_result["error"]) then
        while (order_result["pending"].to_f > 0)
          sleep 1
          order_result = cex_api.get_order(order_result["id"])
          puts "[DEBUG]:   Orden en CEXio #{order_result}"
#          puts "  Order ID: #{order_result["id"]}"
#          puts "  Order Complete: #{order_result["complete"]}"
#          puts "  Order Price: #{order_result["price"]}"
#          puts "  Order Amount: #{order_result["amount"]}"
#          puts "  Order Pending: #{order_result["pending"]}"
#          puts "  Order Remains: #{order_result["remains"]}"
          if (order_result["remains"]) then
            order_result["pending"] = order_result["remains"]
          else
            order_result["pending"] = 0
          end
 #         puts "  Order Pending New: #{order_result["pending"]}"
          if (api_test_flag == 1) then
            order_result["pending"] = 0
          end
        end
        if (order_result["complete"]) then
          order_result = cex_api.get_order(order_result["id"])
        end
        puts "[DEBUG]: Ultimo Orden en CEXio #{order_result}"
        if (api_test_flag == 1) then
          usd_collected = usd_to_receive
        else
          usd_collected = 0
          if (order_result["tta:USD"]) then
            usd_collected = usd_collected + order_result["tta:USD"].to_f - order_result["tfa:USD"].to_f
          end
          if (order_result["ta:USD"]) then
            usd_collected = usd_collected + order_result["ta:USD"].to_f - order_result["fa:USD"].to_f
          end
          puts "[INFO]: CEXIO_ASK: ID #{order_result["id"]}, STATUS #{order_result["complete"]}, USD #{usd_collected.round(2)}, BTC -#{order_result["a:BTC:cds"].to_f.round(8)}, PRICE #{order_result["price"].to_f.round(2)}"
        end
        if (usd_collected > 0) then
#          puts "=="
#          puts "Creamos la orden de compra en CEXio por si baja el bitcoin"
          btc_to_buy = btc_to_sell * (1 + margin_to_win)
          puts "[DEBUG]: Compamos #{btc_to_buy} bitcoins para ganar un margin #{margin_to_win}"
          price_to_bid = (usd_collected * (1 - cexio_commission_maker)) / btc_to_buy
          puts "[DEBUG]: Queremos pagar USD #{price_to_bid}"
          if (api_test_flag == 1) then
            price_to_bid = 100
            puts "[DEBUG]: La orden sale para pagar USD 100"
          end
          bid_result = cex_api.place_order('buy', btc_to_buy.round(8), price_to_bid.round(1), 'BTC/USD')
          puts "[DEBUG]: Bid result en CEXio #{bid_result}"
          puts "[INFO]: CEXIO_BID: ID #{bid_result["id"]}, STATUS #{bid_result["complete"]}, USD -#{usd_collected.round(2)}, BTC #{bid_result["amount"].to_f.round(8)}, PRICE #{bid_result["price"].to_f.round(2)}"
        end
        usd_collected

      else
        puts "[DEBUG]: Algo paso que no su pudo poner la orden en CEXio"
        puts "[DEBUG]: #{order_result}"
        0
      end
    else
      puts "[INFO]: No tenemos BTC disponibles en CEXio para vender"
      0
    end
  end

  def self.MakeTransactionCEXioRev(usd_to_invest = 0, price_to_pay = 100)
    api_test_flag = 0

    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    cexio_commission_taker = 0.0025
    cexio_commission_maker = 0.0016
    margin_to_win = 0.02 # 2%

    if (usd_to_invest > 0) then

      btc_to_buy = usd_to_invest / price_to_pay * (1 - cexio_commission_taker) 
      puts "[DEBUG]: Recibiriamos #{btc_to_buy.round(8)} BTC"
      if (api_test_flag == 1) then
        puts "[DEBUG]: La orden sale para pagar maximo USD 1500" # Cambiamos price_to_pay a 1 por ahora
        price_to_pay = 5000 # Override en test
      end
      order_result = cex_api.place_order('buy', btc_to_buy, price_to_pay, 'BTC/USD')
      puts "[DEBUG]: Orden en CEXio #{order_result}"
      
      if !(order_result["error"]) then
        while (order_result["pending"].to_f > 0)
          sleep 1
          order_result = cex_api.get_order(order_result["id"])
          puts "[DEBUG]:   Orden en CEXio #{order_result}"
          if (order_result["remains"]) then
            order_result["pending"] = order_result["remains"]
          else
            order_result["pending"] = 0
          end
          if (api_test_flag == 1) then
            order_result["pending"] = 0
          end
        end
        if (order_result["complete"]) then
          order_result = cex_api.get_order(order_result["id"])
        end
        puts "[DEBUG]: Ultimo Orden en CEXio #{order_result}"

        if (api_test_flag == 1) then
          produced_quantity = btc_to_buy
        else
          produced_quantity = 0
          if (order_result["a:BTC:cds"]) then
            produced_quantity = produced_quantity + order_result["a:BTC:cds"].to_f
          end
          puts "[INFO]: CEXIO_BID: ID #{order_result["id"]}, STATUS #{order_result["complete"]}, BTC #{produced_quantity.round(8)}, BTC -#{order_result["a:USD:cds"].to_f.round(2)}, PRICE #{order_result["price"].to_f.round(2)}"
        end

        if (produced_quantity > 0) then

          btc_to_sell = produced_quantity * (1 - margin_to_win)
          puts "[DEBUG]: Vendemos #{btc_to_sell} para ganar un #{margin_to_win}"
          price_to_ask = (usd_to_invest / (1 - cexio_commission_maker)) / btc_to_sell
          puts "[DEBUG]: Queremos que nos paguen #{price_to_ask}"

          if (api_test_flag == 1) then
            price_to_ask = 35000 # Override en test
            puts "[DEBUG]: La orden sale para que nos paguen USD 35.000" # Override en test
          end

          ask_result = cex_api.place_order('sell', btc_to_sell.round(8), price_to_ask.round(1), 'BTC/USD')
          puts "[DEBUG]: Ask result en CEXio #{ask_result}"
          puts "[INFO]: CEXIO_ASK: ID #{ask_result["id"]}, STATUS #{ask_result["complete"]}, USD #{usd_to_invest.round(2)}, BTC -#{ask_result["amount"].to_f.round(8)}, PRICE #{ask_result["price"].to_f.round(2)}"
        end
        produced_quantity

      else
        puts "[DEBUG]: Algo paso que no su pudo poner la orden en CEXio"
        puts "[DEBUG]: #{order_result}"
        0
      end

    else
      puts "No hay fondos para operar"
      0
    end
  end

  def self.GetBTCAvailableCEXio
    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    cexio_balance = cex_api.balance
#    puts "[DEBUG]: #{cexio_balance}"
    cexio_balance["BTC"]["available"].to_f
  end

  def self.GetUSDAvailableCEXio
    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    cexio_balance = cex_api.balance
#    puts "[DEBUG]: #{cexio_balance}"
    cexio_balance["USD"]["available"].to_f
  end

  def self.MakeTransactionBitex(usd_to_invest = 0)
    api_test_flag = 0

    Bitex.api_key = BitexMFSettings::Settings.bitex_api_write_key
    bitex_commission = 0.005
    margin_to_win = 0.02 # 2%

    if (usd_to_invest > 0) then
#      puts "Colocamos orden de compra en Bitex"
      bitex_ticker = Bitex::BitcoinMarketData.ticker
      puts "[DEBUG]: El ASK en Bitex es: #{bitex_ticker[:ask]}"
      price_to_pay = bitex_ticker[:ask]
#      puts "El precio a pagar seria: #{price_to_pay}"
      btc_to_receive = usd_to_invest / price_to_pay * (1 - bitex_commission) 
      puts "[DEBUG]: Recibiriamos #{btc_to_receive} BTC"
      if (api_test_flag == 1) then
        puts "[DEBUG]: La orden sale para pagar maximo USD 1" # Cambiamos price_to_pay a 1 por ahora
        price_to_pay = 1 # Override en test
      end
      order_result = Bitex::Bid.create!(:btc, usd_to_invest, price_to_pay)
      puts "[DEBUG]: Order ID: #{order_result.id}"
      puts "[DEBUG]: Order Status: #{order_result.status}"
#      puts "Order Price: #{order_result.price}"
#      puts "Order Amount: #{order_result.amount}"
      if (order_result.status == :received) then
        if (api_test_flag == 1) then
          loop_until_flag = :executing
        else
            loop_until_flag = :completed
        end
        while (order_result.status != loop_until_flag)
          sleep 1
          order_result = Bitex::Bid.find(order_result.id)
          puts "[DEBUG]:   Order ID: #{order_result.id}"
          puts "[DEBUG]:   Order Status: #{order_result.status}"
#          puts "  Order Price: #{order_result.price}"
#          puts "  Order Amount: #{order_result.amount}"
          puts "[DEBUG]:   Order Remaining Amount: #{order_result.remaining_amount}"
          puts "[DEBUG]:   Order Produced quantity: #{order_result.produced_quantity}"
        end
        if (api_test_flag == 1) then
          produced_quantity = btc_to_receive # Override en test
        else 
          produced_quantity = order_result.produced_quantity
        end
        if (produced_quantity > 0) then
          puts "[INFO]: BITEX_BID: ID #{order_result.id}, STATUS #{order_result.status}, USD -#{order_result.amount.round(2)}, BTC #{order_result.produced_quantity.round(8)}, PRICE #{order_result.price.round(2)}"
#          puts "=="
#          puts "Creamos la orden de venta en Bitex para cuando suba el bitcoin recuperar los dolares"
          btc_to_sell = produced_quantity * (1 - margin_to_win)
          puts "[DEBUG]: Vendemos #{btc_to_sell} para ganar un #{margin_to_win}"
          price_to_ask = (usd_to_invest / (1 - bitex_commission)) / btc_to_sell
          puts "[DEBUG]: Queremos que nos paguen #{price_to_ask}"
          if (api_test_flag == 1) then
            price_to_ask = 100000 # Override en test
            puts "[DEBUG]: La orden sale para que nos paguen USD 100.000" # Override en test
          end
          ask_result = Bitex::Ask.create!(:btc, btc_to_sell, price_to_ask)
          puts "[DEBUG]:   Ask ID: #{ask_result.id}"
          puts "[DEBUG]:   Ask Status: #{ask_result.status}"
          puts "[DEBUG]:   Ask Price: #{ask_result.price}"
          puts "[DEBUG]:   Ask Quantity: #{ask_result.quantity}"
          puts "[INFO]: BITEX_ASK: ID #{ask_result.id}, STATUS #{ask_result.status}, USD #{usd_to_invest.round(2)}, BTC -#{ask_result.quantity.round(8)}, PRICE #{ask_result.price.round(2)}"
        end
        produced_quantity
      else
        puts "[DEBUG]: Algo paso que no se pudo poner la orden"
        puts "[DEBUG]: Order ID: #{order_result.id}"
        puts "[DEBUG]: Order Status: #{order_result.status}"
        puts "[DEBUG]: Order Price: #{order_result.price}"
        puts "[DEBUG]: Order Amount: #{order_result.amount}"
        0
      end
    else
      puts "No hay fondos para operar"
      0
    end
  end

  def self.MakeTransactionBitexRev(btc_to_sell = 0)
    api_test_flag = 0

    Bitex.api_key = BitexMFSettings::Settings.bitex_api_write_key
    bitex_commission = 0.005
    margin_to_win = 0.02 # 2%

    if ((api_test_flag == 1) && (btc_to_sell == 0)) then
      btc_to_sell = 0.005
    end

    if (btc_to_sell > 0) then
      bitex_ticker = Bitex::BitcoinMarketData.ticker
      puts "[DEBUG]: El BID en Bitex es: #{bitex_ticker[:bid]}"
      price_to_ask = bitex_ticker[:bid]
      usd_to_receive = btc_to_sell * price_to_ask * (1 - bitex_commission)
      puts "[DEBUG]: Los USD a recibir serian: #{usd_to_receive}"
      if (api_test_flag == 1) then
        price_to_ask = 100000
        puts "[DEBUG]: Ponemos la orden pidiendo USD 100.000"
      end

      order_result = Bitex::Ask.create!(:btc, btc_to_sell, price_to_ask)
      puts "[DEBUG]: Order ID: #{order_result.id}"
      puts "[DEBUG]: Order Status: #{order_result.status}"

      if (order_result.status == :received) then
        if (api_test_flag == 1) then
          loop_until_flag = :executing
        else
            loop_until_flag = :completed
        end
        while (order_result.status != loop_until_flag)
          sleep 1
          order_result = Bitex::Ask.find(order_result.id)
          puts "[DEBUG]:   Order ID: #{order_result.id}"
          puts "[DEBUG]:   Order Status: #{order_result.status}"
          puts "[DEBUG]: Order: #{order_result}"
#          puts "  Order Price: #{order_result.price}"
#          puts "  Order Amount: #{order_result.amount}"
#          puts "[DEBUG]:   Order Remaining Amount: #{order_result.remaining_amount}"
#          puts "[DEBUG]:   Order Produced quantity: #{order_result.produced_quantity}"
        end
        if (api_test_flag == 1) then
          produced_quantity = usd_to_receive # Override en test
        else 
          produced_quantity = order_result.produced_amount
        end
        usd_collected = 0
        if (produced_quantity > 0) then
          usd_collected = produced_quantity
          puts "[INFO]: BITEX_ASK: ID #{order_result.id}, STATUS #{order_result.status}, USD #{order_result.produced_amount}, BTC -#{order_result.quantity}, PRICE #{order_result.price}"
#
          btc_to_buy = btc_to_sell * (1 + margin_to_win)
          puts "[DEBUG]: Compamos #{btc_to_buy} bitcoins para ganar un margin #{margin_to_win}"
          price_to_bid = (usd_collected * (1 - bitex_commission)) / btc_to_buy
          puts "[DEBUG]: Queremos pagar USD #{price_to_bid}"
          if (api_test_flag == 1) then
            price_to_bid = 100
            puts "[DEBUG]: La orden sale para pagar USD 100"
          end

          bid_result = Bitex::Bid.create!(:btc, usd_collected, price_to_bid.round(2))
          puts "[DEBUG]: Bid ID: #{bid_result.id}"
          puts "[DEBUG]: Bid Status: #{bid_result.status}"
          puts "[INFO]: BITEX_BID: ID #{bid_result.id}, STATUS #{bid_result.status}, USD #{bid_result.amount}, BTC #{btc_to_buy}, PRICE #{price_to_bid}"

        end
        usd_collected

      else
        puts "[DEBUG]: Algo paso que no su pudo poner la orden en Bitex"
        puts "[DEBUG]: #{order_result}"
        0
      end
    else
      puts "[INFO]: No tenemos BTC disponibles en Bitex para vender"
      0
    end
  end

  def self.GetUSDAvailableBitex
    #BITEX
    Bitex.api_key = BitexMFSettings::Settings.bitex_api_read_key
    bitex_profile_get = Bitex::Profile.get
    bitex_profile_get[:usd_available]
  end

  def self.GetBTCAvailableBitex
    #BITEX
    Bitex.api_key = BitexMFSettings::Settings.bitex_api_read_key
    bitex_profile_get = Bitex::Profile.get
    bitex_profile_get[:btc_available]
  end

  def self.TickersView
  	cex_api = CEX::API.new('','','')
    max_spread_with_fees = 0
    ciclos = 3600 * 6
  	while (ciclos > 0)
      bitstamp_ticker = Bitstamp.ticker
    	bitex_ticker = Bitex::BitcoinMarketData.ticker
  		cexio_ticker = cex_api.ticker('BTC/USD')
      puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
      puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
      puts "CEXio Ticker: #{cexio_ticker["last"]}. bid: #{cexio_ticker["bid"]} - ask: #{cexio_ticker["ask"]}"

      if (bitex_ticker[:bid] > bitstamp_ticker.bid.to_f) then
        bid_max = bitex_ticker[:bid]
        bid_max_exchange = "BITEX"
      elsif (bitstamp_ticker.bid.to_f > cexio_ticker["bid"]) then
        bid_max = bitstamp_ticker.bid.to_f
        bid_max_exchange = "BITSTAMP"
      else
          bid_max = cexio_ticker["bid"]
          bid_max_exchange = "CEXIO"
      end

      puts "MAX BID: #{bid_max} @ #{bid_max_exchange}"

      if (bitex_ticker[:ask] < bitstamp_ticker.ask.to_f) then
        ask_min = bitex_ticker[:ask]
        ask_min_exchange = "BITEX"
      elsif (bitstamp_ticker.ask.to_f < cexio_ticker["ask"]) then
        ask_min = bitstamp_ticker.bid.to_f
        ask_min_exchange = "BITSTAMP"
      else
          ask_min = cexio_ticker["bid"]
          ask_min_exchange = "CEXIO"
      end

      puts "MIN ASK: #{ask_min} @ #{ask_min_exchange}"

      best_spread = ask_min / bid_max
      puts "BEST SPREAD: #{best_spread}, buy @ #{ask_min_exchange} and sell @ #{bid_max_exchange}"

  		sleep 1
  		ciclos = ciclos - 1
  	end
  end

  def self.TickerAnalysisBitexCEXio
    cex_api = CEX::API.new('','','')
    max_spread_with_fees = 0
    ciclos = 3600 * 6
    while (ciclos > 0)
      bitex_ticker = Bitex::BitcoinMarketData.ticker
      cexio_ticker = cex_api.ticker('BTC/USD')
      bitex_cexio_spread = 1 - (bitex_ticker[:ask] / cexio_ticker["bid"])
      spread_with_fees = bitex_cexio_spread - (0.005 + 0.0025)

      if (spread_with_fees > max_spread_with_fees) then
        puts "Ciclos: #{ciclos}"
        puts "BUY in Bitex @ #{bitex_ticker[:ask]} and SELL in CEXio @ #{cexio_ticker["bid"]} - SPREAD: #{bitex_cexio_spread} (#{spread_with_fees})"
        max_spread_with_fees = spread_with_fees
      end

      sleep 1
      ciclos = ciclos - 1
    end
  end

=begin
# This is a preliminar TickerAnalysis that was not usefull

    # BIDs
    if (bitstamp_ticker.bid.to_f > cexio_ticker["bid"]) then
      bid_high = bitstamp_ticker.bid.to_f
      bid_exchange = "BITSTAMP"
    else
      bid_high = cexio_ticker["bid"]
      bid_exchange = "CEXIO"
    end
    bid_spread = bitex_ticker[:ask] / bid_high
      if bid_spread < 0.9925 then
#       puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
#       puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
        puts " >>> Comprar en BITEX a #{bitex_ticker[:ask]} y vender en #{bid_exchange} a #{bid_high}. Spread: #{bid_spread}"
      else
        puts "BID spread not enough: #{bid_spread}"
      end

      if bid_spread < bid_spread_max then
        bid_spread_max = bid_spread
        bid_exchange_max = bid_exchange
      end

      #ASKs
      ask_spread = bitex_ticker[:ask] / bitstamp_ticker.ask.to_f


      if ask_spread > 1.0076 then
#       puts "Bitex Ticker: #{bitex_ticker[:last]}. bid: #{bitex_ticker[:bid]} - ask: #{bitex_ticker[:ask]}"
#       puts "Bitstamp Ticker: #{bitstamp_ticker.last}. bid: #{bitstamp_ticker.bid} - ask: #{bitstamp_ticker.ask}"
        puts " >>> Vender en BITEX a #{bitex_ticker[:ask]} y comprar en BITSTAMP a #{bitstamp_ticker.ask}"
      else
        puts "ASK spread not enough: #{ask_spread}"
      end
      if ask_spread < ask_spread_max then
        ask_spread_max = ask_spread_max
      end
=end


  def self.CEXioGetOrder(order_id = 0)
    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    order_result = cex_api.get_order(order_id)
    puts order_result
  end

  def self.CEXioPutBuyOrder(btc_to_sell = 0, usd_collected = 0)
    api_test_flag = 0

    cex_api = CEX::API.new(BitexMFSettings::Settings.cexio_userid, BitexMFSettings::Settings.cexio_key, BitexMFSettings::Settings.cexio_secret)
    cexio_commission_taker = 0.0025
    cexio_commission_maker = 0.0016

        if (usd_collected > 0) then
          puts "=="
          puts "Creamos la orden de compra en CEXio por si baja el bitcoin"
          margin_to_win = 0.01 # 1%
          btc_to_buy = btc_to_sell * (1 + margin_to_win)
          puts "Compamos #{btc_to_buy} bitcoins para ganar un margin #{margin_to_win}"
          price_to_bid = (usd_collected * (1 - cexio_commission_maker)) / btc_to_buy
          puts "Queremos pagar USD #{price_to_bid}"
          if (api_test_flag == 1) then
            price_to_bid = 100
            puts "La orden sale para pagar USD 100"
          end
          bid_result = cex_api.place_order('buy', btc_to_buy.round(8), price_to_bid.round(1), 'BTC/USD')
          puts "Bid result en CEXio"
          puts bid_result
        end
  end


end
