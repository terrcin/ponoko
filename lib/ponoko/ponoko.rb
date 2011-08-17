require 'net/https'
require 'uri'

require 'ponoko/ponoko_api.rb'

module Ponoko
  def self.api= a
    @api = a
  end
  
  def self.api
    @api
  end
  
  class Sandbox
    def self.step_order order
      resp = Ponoko::api.step_order order.key
      order.update resp['order']
    end
  end

  class Base
    attr_accessor :ref, :key
    attr_accessor :created_at, :updated_at

    def initialize params = {}
      update params
    end
    
    def update params
      params.each do |k,v|
        send("#{k.gsub('?', '')}=", v)
      end
    end

    def self.ponoko_object
      self.to_s.split('::').last.downcase
    end

    def self.ponoko_objects
      "#{ponoko_object}s"
    end

    def self.get! key = nil
      resp = Ponoko::api.send "get_#{ponoko_objects}", key
      if key.nil?
        resp[ponoko_objects].collect do |p|
          new(p)
        end
      else
        new resp[ponoko_object]
      end
    end
    
    def update!
      resp = Ponoko::api.send "get_#{self.class.ponoko_objects}", key
      update resp[self.class.ponoko_object]
    end
    
  end
  
  class Product < Base
    attr_accessor :name, :description, :materials_available, :locked, :total_make_cost, :node_key
    attr_reader   :designs
    
    private :total_make_cost, :locked
    
    def send!
      raise Ponoko::PonokoAPIError, "Product must have a design." if designs.empty?
      resp = Ponoko::api.post_product self.to_params
      update resp['product']
      self
    end

    def initialize params = {}
      @designs = []
      super params
    end
    
    def locked?
      @locked
    end
    
    def materials_available?
      @materials_available
    end    

    def designs= designs
      @designs = []
      designs.each do |d|
        add_designs Design.new(d)
      end
    end
    
    private :designs=
    
    def add_designs *designs
      designs.each do |d|
        @designs << d
      end
    end
    
    def to_params
      raise Ponoko::PonokoAPIError, "Product must have a Design." if designs.empty?
      {ref => ref, 'name' => name, 'description' => description, 'designs' => @designs.to_params}
    end
    
    def making_cost
      total_make_cost['making'].to_f
    end
    
    def materials_cost
      total_make_cost['materials'].to_f
    end
    
    def total_cost
      total_make_cost['total'].to_f
    end
    
  end
  
  class Design < Base
    attr_accessor :make_cost, :material_key, :design_file, :filename, :size, :quantity
    attr_accessor :content_type
    attr_reader   :material

    private :make_cost
  
    def add_material material
       @material = material
    end
    
    def making_cost
      make_cost['making'].to_f
    end
    
    def material_cost
      make_cost['material'].to_f
    end
    
    def total_cost
      make_cost['total'].to_f
    end
    
    def to_params
      raise Ponoko::PonokoAPIError, "Design must have a Material." if material.nil?
      {'uploaded_data' => design_file, 'ref' => ref, 'material_key' => material.to_params}
    end   
  end
  
  class Material < Base
    attr_accessor :type, :weight, :color, :thickness, :name, :width, :material_type
    attr_accessor :length, :kind
    attr_accessor :updated_at
    
    def to_params
      key
    end
  end
  
  class Address
    attr_accessor :first_name, :last_name, :address_line_1, :address_line_2, :city
    attr_accessor :state, :zip_or_postal_code, :country, :phone_number
    
    def initialize first_name, last_name, address_line_1, address_line_2, city, state, zip_or_postal_code, country, phone_number
      @first_name = first_name
      @last_name = last_name
      @address_line_1 = address_line_1
      @address_line_2 = address_line_2
      @city = city
      @state = state
      @zip_or_postal_code = zip_or_postal_code
      @country = country
      @phone_number = phone_number
    end
    
    def to_params    
      h = {}
      public_methods(false).each do |m|
        next if m[-1] == '='
        next if m == :to_params
        h[m.to_s] = self.send(m)
      end
      h
    end
  end
    
  class Order < Base
    attr_accessor :shipped, :delivery_address, :events, :shipping_option_code
    attr_accessor :last_successful_callback_at, :quantity, :tracking_numbers, :currency
    attr_accessor :node_key, :cost
    attr_accessor :products
    
    private :cost, :shipped
    
    def initialize params = {}
      @events = []
      @products = []
      @delivery_address = nil
      @billing_address = nil
      super
    end
    
    def send!
      raise Ponoko::PonokoAPIError, "Order must have a Shipping Option Code" if shipping_option_code.nil?
      raise Ponoko::PonokoAPIError, "Order must have Products" if products.empty?

      resp = Ponoko::api.post_order self.to_params
      update resp['order']
      self
    end
    
    def add_product product, quantity = 1
      @products << {'product' => product, 'quantity' => quantity.to_s}
    end
    
    def make_cost
      cost['making'].to_f
    end
    
    def material_cost
      cost['materials'].to_f
    end
    
    def shipping_cost
      cost['shipping'].to_f
    end
    
    def total_cost
      cost['total'].to_f
    end
    
    def shipped?
      @shipped
    end
    
    def status!
      resp = Ponoko::api.get_order_status key
      update resp['order']
      status
    end
    
    def status
      status! if @events.empty?
      @events.last['name']
    end
    
    def shipping_options!
      resp = Ponoko::api.get_shipping_options self.to_params
      resp['shipping_options']['options']
    end
    
    def to_params
      raise Ponoko::PonokoAPIError, "Order must have a Delivery Address" if delivery_address.nil?
      raise Ponoko::PonokoAPIError, "Order must have Products" if products.empty?
      
      params = {}
      products = @products.collect do |p|
        {'key' => p['product'].key, 'quantity' => p['quantity']}
      end
      
      params['ref'] = ref
      params['products'] = products
      params['shipping_option_code'] = shipping_option_code unless shipping_option_code.nil?
      params['delivery_address'] = delivery_address.to_params
      
      params
    end
  end
  
  class Node < Base
    attr_accessor :name, :materials_updated_at, :count, :last_updated
    
    def initialize params = {}
      super
    end
    
    def materials= materials
      @material_catalogue = MaterialCatalogue.new
      materials.each do |m|
        @material_catalogue.make_material m
      end
    end
    
    private :materials=
    
    def material_catalogue!
      materials_date = materials_updated_at
      update!

      if @material_catalogue.nil? || materials_updated_at > materials_date
        resp = Ponoko::api.get_material_catalogue key
        raise Ponoko::PonokoAPIError, "Unknown Error Occurred" unless key ==  resp['key']
        update resp
      end
      
      material_catalogue
    end

    def material_catalogue
      material_catalogue! if @material_catalogue.nil?
      @material_catalogue
    end
  end
  
  class MaterialCatalogue
    attr_reader :materials

    def initialize
      @materials = []
      @catalogue = Hash.new{|h,k| h[k] = Hash.new(&h.default_proc) }
    end

    def make_material material
      m = Material.new(material)
      @materials << m
      @catalogue[m.kind][m.name][m.color][m.thickness][m.type] = m
    end
    
    def [] key
      @catalogue[key]
    end
    
    def count
      @materials.length
    end
  end
  
end # module Ponoko  
  