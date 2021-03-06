module Bat
  class Requirements
    include RSpec::Matchers

    def initialize(stemcell_path, bosh_runner, bosh_api, spec_state, logger)
      @stemcell_path = stemcell_path
      @bosh_runner = bosh_runner
      @bosh_api = bosh_api
      @spec_state = spec_state
      @logger = logger
    end

    def stemcell
      @stemcell ||= Bat::Stemcell.from_path(@stemcell_path)
    end

    def release
      release_dir = File.join(SPEC_ROOT, 'system', 'assets', 'bat-release')
      @release ||= Bat::Release.from_path(release_dir)
    end

    def previous_release
      @previous_release ||= release.previous
    end

    def requirement(what, deployment_spec = nil, options = {})
      @logger.info("Requirement #{what}")
      case what
        when Bat::Stemcell
          require_stemcell(what)
        when Bat::Release
          require_release(what)
        when Bat::Deployment
          require_deployment(what, deployment_spec, options)
        when :no_tasks_processing
          if tasks_processing?
            raise 'director is currently processing tasks'
          end
        else
          raise "unknown requirement: #{what}"
      end
      @logger.info("Satisfied requirement #{what}")
    end

    def cleanup(what)
      if @spec_state.skip_cleanup?
        @logger.info("Skipping cleanup #{what}")
        return
      end

      @logger.info("Starting cleanup #{what}")
      case what
        when Bat::Stemcell
          if @bosh_api.stemcells.include?(what)
            expect(@bosh_runner.bosh_safe("delete stemcell #{what.name} #{what.version}")).to succeed
          end
        when Bat::Release
          if @bosh_api.releases.include?(what)
            expect(@bosh_runner.bosh_safe("delete release #{what.name}")).to succeed
          end
        when Bat::Deployment
          if @bosh_api.deployments.include?(what.name)
            expect(@bosh_runner.bosh_safe("delete deployment #{what.name}")).to succeed
            what.delete
          end
        else
          raise "unknown cleanup: #{what}"
      end
      @logger.info("Cleaned up #{what}")
    end

    def tasks_processing?
      # `bosh tasks` exit code is 1 if no tasks running
      @bosh_runner.bosh('tasks', on_error: :return).output =~ /\| processing \|/
    end

    private

    def require_stemcell(what)
      if @bosh_api.stemcells.include?(what)
        @logger.info('Stemcell already uploaded')
      else
        @logger.info('stemcell not uploaded')
        expect(@bosh_runner.bosh_safe("upload stemcell #{what.to_path}")).to succeed
      end
    end

    def require_release(what)
      if @bosh_api.releases.include?(what)
        @logger.info('release already uploaded')
      else
        @logger.info('release not uploaded')
        expect(@bosh_runner.bosh_safe("upload release #{what.to_path}")).to succeed
      end
    end

    def require_deployment(what, deployment_spec, options)
      if @bosh_api.deployments.include?(what.name) && !options[:force]
        @logger.info('deployment already deployed, skipping deployment')
        expect(@bosh_runner.bosh_safe("deployment #{what.to_path}")).to succeed
      else
        @logger.info('deployment not already deployed, deploying...')
        what.generate_deployment_manifest(deployment_spec)
        expect(@bosh_runner.bosh_safe("deployment #{what.to_path}")).to succeed
        expect(@bosh_runner.bosh_safe('deploy')).to succeed
      end
    rescue
      @spec_state.register_fail
      raise
    end
  end
end
