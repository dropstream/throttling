require 'spec_helper'

describe Throttling do
  before do
    Throttling.reset_defaults!
    @storage = Throttling.storage = TestStorage.new
  end

  describe 'instance methods' do
    before do
      Throttling.limits = { 'foo' => {'limit' => 5, 'period' => 2} }
      @t = Throttling.for('foo')
    end

    { :check_ip => '127.0.0.1', :check_user_id => 123 }.each do |check_method, valid_value|
      describe check_method do
        it 'should return true for nil check_values' do
          expect(@t.send(check_method, nil)).to be_true
        end

        it 'should return true if no limit specified in configs' do
          Throttling.limits['foo']['limit'] = nil
          expect(@storage).to receive(:fetch).and_return(1000)
          expect(@t.send(check_method, valid_value)).to be_true
        end

        it 'should return false if limit is 0' do
          Throttling.limits['foo']['limit'] = 0
          expect(@storage).to receive(:fetch).and_return(0)
          expect(@t.send(check_method, valid_value)).to be_false
        end

        it 'should raise an exception if no period specified in configs' do
          Throttling.limits['foo']['period'] = nil
          expect { @t.send(check_method, valid_value) }.to raise_error(ArgumentError)
        end

        it 'should raise an exception if invalid period specified in configs' do
          Throttling.limits['foo']['period'] = -1
          expect { @t.send(check_method, valid_value) }.to raise_error(ArgumentError)

          Throttling.limits['foo']['period'] = 'foo'
          expect { @t.send(check_method, valid_value) }.to raise_error(ArgumentError)
        end

        it 'should return true if throttling limit is not passed' do
          expect(@storage).to receive(:fetch).and_return(1)
          expect(@t.send(check_method, valid_value)).to be_true
        end

        it 'should return false if throttling limit is passed' do
          expect(@storage).to receive(:fetch).and_return(Throttling.limits['foo']['limit'] + 1)
          expect(@t.send(check_method, valid_value)).to be_false
        end

        context 'around limit' do
          it 'should increase hit counter when values equals to limit - 1' do
            expect(@storage).to receive(:fetch).and_return(Throttling.limits['foo']['limit'] - 1)
            expect(@storage).to receive(:increment)
            @t.send(check_method, valid_value)
          end

          it 'should not increase hit counter when values equals to limit' do
            expect(@storage).to receive(:fetch).and_return(Throttling.limits['foo']['limit'])
            expect(@storage).not_to receive(:increment)
            @t.send(check_method, valid_value)
          end

          it 'should not increase hit counter when values equals to limit + 1' do
            expect(@storage).to receive(:fetch).and_return(Throttling.limits['foo']['limit'] + 1)
            expect(@storage).not_to receive(:increment)
            @t.send(check_method, valid_value)
          end

          it 'should allow exactly limit actions' do
            5.times { expect(@t.send(check_method, valid_value)).to be_true }
            expect(@storage).not_to receive(:increment)
            expect(@t.send(check_method, valid_value)).to be_false
          end
        end
      end
    end
  end

  describe 'with multi-level limits' do
    before do
      Throttling.limits = { 'foo' => { 'two' => { 'limit' => 10, 'period' => 20 }, 'one' => { 'limit' => 5, 'period' => 2 } } }
    end

    it 'should return false if at least one limit is reached' do
      expect(@storage).to receive(:fetch).and_return(1, 100)
      expect(Throttling.for('foo').check_ip('127.0.0.1')).to be_false
    end

    it 'should return true if none limits reached' do
      expect(@storage).to receive(:fetch).and_return(1, 2)
      expect(Throttling.for('foo').check_ip('127.0.0.1')).to be_true
    end

    it 'should sort limits by period' do
      expect(@storage).to receive(:fetch).ordered.with(/\:one\:/, anything).and_return(0)
      expect(@storage).to receive(:fetch).ordered.with(/\:two\:/, anything).and_return(0)
      expect(Throttling.for('foo').check_ip('127.0.0.1')).to be_true
    end

    it 'should return as soon as limit reached' do
      expect(@storage).to receive(:fetch).ordered.with(/\:one\:/, anything).and_return(10)
      expect(@storage).not_to receive(:fetch).with(/\:two\:/)
      expect(Throttling.for('foo').check_ip('127.0.0.1')).to be_false
    end
  end

  context 'with values specified' do
    before do
      Throttling.limits_config = File.expand_path('../fixtures/throttling.yml', __FILE__)
    end

    it 'should return value when limit is not reached' do
      expect(@storage).to receive(:fetch).and_return(0)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(10)
      expect(@storage).to receive(:fetch).and_return(4)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(10)

      expect(@storage).to receive(:fetch).and_return(5)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(15)
      expect(@storage).to receive(:fetch).and_return(14)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(15)

      expect(@storage).to receive(:fetch).and_return(15)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(20)
      expect(@storage).to receive(:fetch).and_return(99)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(20)

      expect(@storage).to receive(:fetch).and_return(100)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(25)
      expect(@storage).to receive(:fetch).and_return(1000)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to eq(25)
    end

    it 'should increase hit counter' do
      expect(@storage).to receive(:fetch).and_return(4)
      expect(@storage).to receive(:increment)
      Throttling.for('request_priority').check_ip('127.0.0.1')

      expect(@storage).to receive(:fetch).and_return(1000)
      expect(@storage).to receive(:increment)
      Throttling.for('request_priority').check_ip('127.0.0.1')
    end

    it 'should return false when highest limit reached' do
      Throttling.limits['request_priority'].delete('default_value')
      expect(@storage).to receive(:fetch).and_return(1000)
      expect(Throttling.for('request_priority').check_ip('127.0.0.1')).to be_false
    end
  end

  context do
    before do
      Throttling.limits = { 'foo' => {'limit' => 5, 'period' => 86400} }
      @timestamp = 1334261569
    end

    describe 'key name' do
      it 'should include type, value, name, and period start' do
        Timecop.freeze(Time.at(@timestamp)) do
          Throttling.for('foo').check_ip('127.0.0.1')
        end
        expect(@storage.values.keys.first).to eq('throttle:foo:ip:127.0.0.1:global:15442')
      end
    end

    describe 'key expiration' do
      it 'should calculate expiration time' do
        Timecop.freeze(Time.at(@timestamp)) do
          Throttling.for('foo').check_ip('127.0.0.1')
        end
        expect(@storage.values.values.first[:expires_in]).to eq(13631)
      end
    end
  end
end
