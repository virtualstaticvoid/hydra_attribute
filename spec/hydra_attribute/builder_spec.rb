require 'spec_helper'

describe HydraAttribute::Builder do

  let(:klass) do
    Class.new do
      define_singleton_method :base_class do
        @base_class ||= Class.new
      end
    end
  end


  let!(:builder) { HydraAttribute::Builder.new(klass) }

  describe '#initialzie' do
    it 'should extend base class with HydraAttribute::Scoped module' do
      klass.base_class.singleton_class.should include(HydraAttribute::Scoped)
    end

    it 'should respond to all supported types' do
      HydraAttribute::SUPPORT_TYPES.each do |type|
        builder.should respond_to(type)
      end
    end
  end

  describe '#string' do
    let(:association_instance) { mock(:association_instance) }
    let(:attribute_instance)   { mock(:attribute_instance) }

    before do
      HydraAttribute::Association.should_receive(:new).with(klass, :string).and_return(association_instance)
      HydraAttribute::Attribute.should_receive(:new).with(klass, :name, :string).and_return(attribute_instance)

      [association_instance, attribute_instance].each { |instance| instance.should_receive(:build) }
    end

    it 'should build association' do
      builder.string :name
    end
  end
end