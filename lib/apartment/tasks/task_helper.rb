# frozen_string_literal: true

module Apartment
  module TaskHelper
    def self.each_tenant(&block)
      run_with_advisory_lock do
        Parallel.each(tenants_without_default, in_threads: Apartment.parallel_migration_threads) do |tenant|
          block.call(tenant)
        end
      end
    end

    def self.tenants_without_default
      tenants - [Apartment.default_tenant]
    end

    def self.tenants
      ENV['DB'] ? ENV['DB'].split(',').map(&:strip) : Apartment.tenant_names || []
    end

    def self.warn_if_tenants_empty
      return unless tenants.empty? && ENV['IGNORE_EMPTY_TENANTS'] != 'true'

      puts <<-WARNING
        [WARNING] - The list of tenants to migrate appears to be empty. This could mean a few things:

          1. You may not have created any, in which case you can ignore this message
          2. You've run `apartment:migrate` directly without loading the Rails environment
            * `apartment:migrate` is now deprecated. Tenants will automatically be migrated with `db:migrate`

        Note that your tenants currently haven't been migrated. You'll need to run `db:migrate` to rectify this.
      WARNING
    end

    def self.create_tenant(tenant_name)
      puts("Creating #{tenant_name} tenant")
      Apartment::Tenant.create(tenant_name)
    rescue Apartment::TenantExists => e
      puts "Tried to create already existing tenant: #{e}"
    end

    def self.migrate_tenant(tenant_name)
      strategy = Apartment.db_migrate_tenant_missing_strategy
      create_tenant(tenant_name) if strategy == :create_tenant

      puts("Migrating #{tenant_name} tenant")
      Apartment::Migrator.migrate(tenant_name)
    rescue Apartment::TenantNotFound => e
      raise e if strategy == :raise_exception

      puts e.message
    end

    def self.run_with_advisory_lock
      # Only use advisory_lock if db adapter supports
      return unless ActiveRecord::Base.connection.supports_advisory_locks?

      # Disable advisory_locks for active record and establish a new connection
      con = Rails.configuration.database_configuration[Rails.env.to_s]
      ActiveRecord::Base.establish_connection(con.merge('advisory_locks' => false))

      # Generate a lock_id borrowing from the ActiveRecord Implemention
      hash_input = ActiveRecord::Base.connection.current_database
      hash_input += ActiveRecord::Base.connection.current_schema if ActiveRecord::Base.connection.respond_to?(:current_schema)
      db_name_hash = Zlib.crc32(hash_input) * 2_053_462_845

      # Obtain advisory_lock
      obtained_lock = ActiveRecord::Base.connection.select_value("select pg_try_advisory_lock(#{db_name_hash});")
      raise ActiveRecord::ConcurrentMigrationError unless obtained_lock

      begin
        yield
      ensure
        # Remove advisory_lock and reset ActiveRecord connection
        ActiveRecord::Base.connection.execute("select pg_advisory_unlock(#{db_name_hash});")
        ActiveRecord::Base.establish_connection(con)
      end
    end
  end
end
