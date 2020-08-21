# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'commander/command'
require_relative '../../lib/vmfloaty/utils'

describe Utils do
  describe '#standardize_hostnames' do
    before :each do
      @vmpooler_response_body = '{
         "ok": true,
         "domain": "delivery.mycompany.net",
         "ubuntu-1610-x86_64": {
           "hostname": ["gdoy8q3nckuob0i", "ctnktsd0u11p9tm"]
         },
         "centos-7-x86_64": {
           "hostname": "dlgietfmgeegry2"
         }
       }'
      @nonstandard_response_body = '{
         "ok": true,
         "solaris-10-sparc": {
           "hostname": ["sol10-10.delivery.mycompany.net", "sol10-11.delivery.mycompany.net"]
         },
         "ubuntu-16.04-power8": {
           "hostname": "power8-ubuntu16.04-6.delivery.mycompany.net"
         }
       }'
    end

    it 'formats a result from vmpooler into a hash of os to hostnames' do
      result = Utils.standardize_hostnames(JSON.parse(@vmpooler_response_body))
      expect(result).to eq('centos-7-x86_64'    => ['dlgietfmgeegry2.delivery.mycompany.net'],
                           'ubuntu-1610-x86_64' => ['gdoy8q3nckuob0i.delivery.mycompany.net', 'ctnktsd0u11p9tm.delivery.mycompany.net'])
    end

    it 'formats a result from the nonstandard pooler into a hash of os to hostnames' do
      result = Utils.standardize_hostnames(JSON.parse(@nonstandard_response_body))
      expect(result).to eq('solaris-10-sparc'    => ['sol10-10.delivery.mycompany.net', 'sol10-11.delivery.mycompany.net'],
                           'ubuntu-16.04-power8' => ['power8-ubuntu16.04-6.delivery.mycompany.net'])
    end
  end

  describe '#format_host_output' do
    before :each do
      @vmpooler_results = {
        'centos-7-x86_64'    => ['dlgietfmgeegry2.delivery.mycompany.net'],
        'ubuntu-1610-x86_64' => ['gdoy8q3nckuob0i.delivery.mycompany.net', 'ctnktsd0u11p9tm.delivery.mycompany.net'],
      }
      @nonstandard_results = {
        'solaris-10-sparc'    => ['sol10-10.delivery.mycompany.net', 'sol10-11.delivery.mycompany.net'],
        'ubuntu-16.04-power8' => ['power8-ubuntu16.04-6.delivery.mycompany.net'],
      }
      @vmpooler_output = <<~OUT.chomp
        - dlgietfmgeegry2.delivery.mycompany.net (centos-7-x86_64)
        - gdoy8q3nckuob0i.delivery.mycompany.net (ubuntu-1610-x86_64)
        - ctnktsd0u11p9tm.delivery.mycompany.net (ubuntu-1610-x86_64)
      OUT
      @nonstandard_output = <<~OUT.chomp
        - sol10-10.delivery.mycompany.net (solaris-10-sparc)
        - sol10-11.delivery.mycompany.net (solaris-10-sparc)
        - power8-ubuntu16.04-6.delivery.mycompany.net (ubuntu-16.04-power8)
      OUT
    end
    it 'formats a hostname hash from vmpooler into a list that includes the os' do
      expect(Utils.format_host_output(@vmpooler_results)).to eq(@vmpooler_output)
    end

    it 'formats a hostname hash from the nonstandard pooler into a list that includes the os' do
      expect(Utils.format_host_output(@nonstandard_results)).to eq(@nonstandard_output)
    end
  end

  describe '#get_service_object' do
    it 'assumes vmpooler by default' do
      expect(Utils.get_service_object).to be Pooler
    end

    it 'uses nspooler when told explicitly' do
      expect(Utils.get_service_object('nspooler')).to be NonstandardPooler
    end
  end

  describe '#get_service_config' do
    before :each do
      @default_config = {
        'url'   => 'http://default.url',
        'user'  => 'first.last.default',
        'token' => 'default-token',
      }
      @services_config = {
        'services' => {
          'vm' => {
            'url'   => 'http://vmpooler.url',
            'user'  => 'first.last.vmpooler',
            'token' => 'vmpooler-token',
          },
          'ns' => {
            'url'   => 'http://nspooler.url',
            'user'  => 'first.last.nspooler',
            'token' => 'nspooler-token',
          },
        },
      }
    end

    it "returns the first service configured under 'services' as the default if available" do
      config = @default_config.merge @services_config
      options = MockOptions.new({})
      expect(Utils.get_service_config(config, options)).to include @services_config['services']['vm']
    end

    it 'allows selection by configured service key' do
      config = @default_config.merge @services_config
      options = MockOptions.new(:service => 'ns')
      expect(Utils.get_service_config(config, options)).to include @services_config['services']['ns']
    end

    it 'uses top-level service config values as defaults when configured service values are missing' do
      config = @default_config.merge @services_config
      config['services']['vm'].delete 'url'
      options = MockOptions.new(:service => 'vm')
      expect(Utils.get_service_config(config, options)['url']).to eq 'http://default.url'
    end

    it "raises an error if passed a service name that hasn't been configured" do
      config = @default_config.merge @services_config
      options = MockOptions.new(:service => 'none')
      expect { Utils.get_service_config(config, options) }.to raise_error ArgumentError
    end

    it 'prioritizes values passed as command line options over configuration options' do
      config = @default_config
      options = MockOptions.new(:url => 'http://alternate.url', :token => 'alternate-token')
      expected = config.merge('url' => 'http://alternate.url', 'token' => 'alternate-token')
      expect(Utils.get_service_config(config, options)).to include expected
    end
  end

  describe '#generate_os_hash' do
    before :each do
      @host_hash = { 'centos' => 1, 'debian' => 5, 'windows' => 1 }
    end

    it 'takes an array of os arguments and returns a formatted hash' do
      host_arg = ['centos', 'debian=5', 'windows=1']
      expect(Utils.generate_os_hash(host_arg)).to eq @host_hash
    end

    it 'returns an empty hash if there are no arguments provided' do
      host_arg = []
      expect(Utils.generate_os_hash(host_arg)).to be_empty
    end
  end

  describe '#pretty_print_hosts' do
    let(:url) { 'http://pooler.example.com' }
    let(:verbose) { nil }
    let(:options) { nil }

    before(:each) do
      allow(service).to receive(:query)
        .with(anything, hostname)
        .and_return(response_body)
    end

    subject { Utils.pretty_print_hosts(verbose, service, hostname, options) }

    describe 'with vmpooler service' do
      let(:service) { Service.new(MockOptions.new, 'url' => url) }

      let(:hostname) { 'mcpy42eqjxli9g2' }
      let(:domain) { 'delivery.mycompany.net' }
      let(:fqdn) { [hostname, domain].join('.') }

      let(:response_body) do
        {
          hostname => {
            'template' => 'ubuntu-1604-x86_64',
            'lifetime' => 12,
            'running'  => 9.66,
            'state'    => 'running',
            'ip'       => '127.0.0.1',
            'domain'   => domain,
          }
        }
      end

      let(:default_output) { "- #{fqdn} (ubuntu-1604-x86_64, 9.66/12 hours)" }

      it 'prints output with host fqdn, template and duration info' do
        expect(STDOUT).to receive(:puts).with(default_output)

        subject
      end

      context 'when tags are supplied' do
        let(:hostname) { 'aiydvzpg23r415q' }
        let(:response_body) do
          {
            hostname => {
              'template' => 'redhat-7-x86_64',
              'lifetime' => 48,
              'running'  => 7.67,
              'state'    => 'running',
              'tags'     => {
                'user' => 'bob',
                'role' => 'agent',
              },
              'ip'       => '127.0.0.1',
              'domain'   => domain,
            }
          }
        end

        it 'prints output with host fqdn, template, duration info, and tags' do
          output = "- #{fqdn} (redhat-7-x86_64, 7.67/48 hours, user: bob, role: agent)"

          expect(STDOUT).to receive(:puts).with(output)

          subject
        end
      end

      context 'when print_to_stderr option is true' do
        let(:options) { { print_to_stderr: true } }

        it 'outputs to stderr instead of stdout' do
          expect(STDERR).to receive(:puts).with(default_output)

          subject
        end
      end

      context 'when hostname_only option is true' do
        let(:options) { { hostname_only: true } }

        it 'prints only the hostname' do
          expect(STDOUT).to receive(:puts).with(fqdn)

          subject
        end
      end
    end

    describe 'with nonstandard pooler service' do
      let(:service) { Service.new(MockOptions.new, 'url' => url, 'type' => 'ns') }

      let(:hostname) { 'sol11-9.delivery.mycompany.net' }
      let(:response_body) do
        {
          hostname => {
            'fqdn'                      => hostname,
            'os_triple'                 => 'solaris-11-sparc',
            'reserved_by_user'          => 'first.last',
            'reserved_for_reason'       => '',
            'hours_left_on_reservation' => 35.89,
          }
        }
      end

      let(:default_output) { "- #{hostname} (solaris-11-sparc, 35.89h remaining)" }

      it 'prints output with host, template, and time remaining' do
        expect(STDOUT).to receive(:puts).with(default_output)

        subject
      end

      context 'when reason is supplied' do
        let(:response_body) do
          {
            hostname => {
              'fqdn'                      => hostname,
              'os_triple'                 => 'solaris-11-sparc',
              'reserved_by_user'          => 'first.last',
              'reserved_for_reason'       => 'testing',
              'hours_left_on_reservation' => 35.89,
            }
          }
        end

        it 'prints output with host, template, time remaining, and reason' do
          output = '- sol11-9.delivery.mycompany.net (solaris-11-sparc, 35.89h remaining, reason: testing)'

          expect(STDOUT).to receive(:puts).with(output)

          subject
        end
      end

      context 'when print_to_stderr option is true' do
        let(:options) { { print_to_stderr: true } }

        it 'outputs to stderr instead of stdout' do
          expect(STDERR).to receive(:puts).with(default_output)

          subject
        end
      end

      context 'when hostname_only option is true' do
        let(:options) { { hostname_only: true } }

        it 'prints only the hostname' do
          expect(STDOUT).to receive(:puts).with(hostname)

          subject
        end
      end
    end

    describe 'with ABS service' do
      let(:service) { Service.new(MockOptions.new, 'url' => url, 'type' => 'abs') }

      let(:hostname) { '1597952189390' }
      let(:fqdn) { 'example-noun.delivery.puppetlabs.net' }
      let(:template) { 'ubuntu-1604-x86_64' }

      # This seems to be the miminal stub response from ABS for the current output
      let(:response_body) do
        {
          hostname => {
            'state' => 'allocated',
            'allocated_resources' => [
              {
                'hostname' => fqdn,
                'type' => template,
                'enging' => 'vmpooler',
              },
            ],
            'request' => {
              'job' => {
                'id' => hostname,
              }
            },
          }
        }
      end

      let(:default_output) { "- [JobID:#{hostname}] #{fqdn} (#{template}) <allocated>" }

      it 'prints output with job id, host, and template' do
        expect(STDOUT).to receive(:puts).with(default_output)

        subject
      end

      context 'when print_to_stderr option is true' do
        let(:options) { { print_to_stderr: true } }

        it 'outputs to stderr instead of stdout' do
          expect(STDERR).to receive(:puts).with(default_output)

          subject
        end
      end

      context 'when hostname_only option is true' do
        let(:options) { { hostname_only: true } }

        it 'prints only the hostname' do
          expect(STDOUT).to receive(:puts).with(fqdn)

          subject
        end
      end
    end
  end
end
