module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module InnovitiUnipay
      mattr_accessor :test_url
      mattr_accessor :production_url

      self.test_url = 'https://unipaynetuat.innoviti.com:13001/FlohNetwork/saleTrans'
      self.production_url = 'https://unipaynet.innoviti.com/FlohNetwork/saleTrans'

      def self.service_url
        OffsitePayments.mode == :production ? self.production_url : self.test_url
      end

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(post, options = {})
        Return.new(post, options)
      end

      def self.checksum(secret_key, payload_items)
        Digest::MD5.hexdigest([*payload_items, secret_key].join("|"))
      end

      class Helper < OffsitePayments::Helper

        CHECKSUM_FIELDS = ['orderId', 'merchantId', 'subMerchantId', 'amt', 'cur', 'proSku', 'Cname', 'mobile', 'emailId', 'redirUrl']

        mapping :amount, 'amt'
        mapping :account, 'merchantId'
        mapping :order, 'orderId'
        mapping :description, 'proSku'
        mapping :processing_code, 'processingCode'
        mapping :submerchant_id, 'subMerchantId'
        mapping :currency, 'cur'

        mapping :customer, :name => 'Cname',
        :email => 'emailId',
        :phone => 'mobile'

        mapping :return_url, 'redirUrl'
        mapping :checksum, 'chksum'

        mapping :merchant_defined, { :var1 => 'mdf1',
          :var2 => 'mdf2',
          :var3 => 'mdf3',
          :var4 => 'mdf4',
          :var5 => 'mdf5'
        }

        def initialize(order, account, options = {})
          super
          @options = options
          add_field('cur', 'INR')
        end


        def form_fields
          @fields.merge(mappings[:checksum] => generate_checksum)
        end

        def generate_checksum
          checksum_payload_items = CHECKSUM_FIELDS.map { |field| @fields[field] }
          InnovitiUnipay.checksum(@options[:credential2], checksum_payload_items)
        end

      end

      class Notification < OffsitePayments::Notification
        def initialize(post, options = {})
          super(post, options)
          @merchant_id = options[:credential1]
          @secret_key = options[:credential2]
        end

        def complete?
          status == "Completed"
        end

        def gross
          0.0
        end

        def status
          case response_code
          when '00' then 'Completed'
          else 'Failed'
          end
        end

        def invoice_ok?(order_id)
          order_id.to_s == invoice.to_s
        end

        def invoice
          item_id
        end

        def response_code
          response_xml.css('resCode').text
        end

        def transaction_id
          response_xml.css('UnipayId').text
        end

        def item_id
          response_xml.css('orderId').text
        end

        def account
          response_xml.css('merchantId').text
        end

        def processing_code
          response_xml.css('procCode').text
        end

        def checksum
          response_xml.css('checkSum').text
        end

        def message
          response_xml.css('resmsg').text
        end

        def acknowledge(authcode = nil)
          checksum_ok?
        end

        def checksum_ok?
          checksum_fields = [invoice, account, transaction_id, response_code, message].join

          unless Digest::MD5.hexdigest([*checksum_fields, @secret_key].join("|")) == checksum
            @message = 'Return checksum not matching the data provided'
            return false
          end
          true
        end

        private
        def response_xml
          Nokogiri::XML.parse(params['transresponse'])
        end
      end

      class Return < OffsitePayments::Return

        def initialize(post, options = {})
          super
          @notification = Notification.new(post, options)
        end

        def status
          if @notification.invoice_ok?(order_id)
            @notification.status
          else
            'Mismatch'
          end
        end

        def success?
          @notification.status == 'Completed'
        end

        def message
          @notification.message
        end
      end
    end
  end
end
