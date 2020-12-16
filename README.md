# Apartment

[![Gem Version](https://badge.fury.io/rb/ros-apartment.svg)](https://badge.fury.io/rb/apartment)
[![Code Climate](https://api.codeclimate.com/v1/badges/b0dc327380bb8438f991/maintainability)](https://codeclimate.com/github/rails-on-services/apartment/maintainability)
[![Build Status](https://travis-ci.org/rails-on-services/apartment.svg?branch=development)](https://travis-ci.org/rails-on-services/apartment)

*Multitenancy for Rails and ActiveRecord*

Apartment provides tools to help you deal with multiple tenants in your Rails
application. If you need to have certain data sequestered based on account or company,
but still allow some data to exist in a common tenant, Apartment can help.

## Apartment drop in replacement gem

After having reached out via github issues and email directly, no replies ever
came. Since we wanted to upgrade our application to Rails 6 we decided to fork
and start some development to support Rails 6. Because we don't have access
to the apartment gem itself, the solution was to release it under a different
name but providing the exact same API as it was before.

## Help wanted

We were never involved with the development of Apartment gem in the first place
and this project started out of our own needs. We will be more than happy
to collaborate to maintain the gem alive and supporting the latest versions
of ruby and rails, but your help is appreciated. Either by reporting bugs you
may find or proposing improvements to the gem itself. Feel free to reach out.

## Installation

### Rails

Add the following to your Gemfile:

```ruby
gem 'ros-apartment', require: 'apartment'
```

Then generate your `Apartment` config file using

```ruby
bundle exec rails generate apartment:install
```

This will create a `config/initializers/apartment.rb` initializer file.
Configure as needed using the docs below.

That's all you need to set up the Apartment libraries. If you want to switch tenants
on a per-user basis, look under "Usage - Switching tenants per request", below.

> NOTE: If using [postgresql schemas](http://www.postgresql.org/docs/9.0/static/ddl-schemas.html) you must use:
>
> * for Rails 3.1.x: _Rails ~> 3.1.2_, it contains a [patch](https://github.com/rails/rails/pull/3232) that makes prepared statements work with multiple schemas

## Usage

### Video Tutorial

How to separate your application data into different accounts or companies.
[GoRails #47](https://gorails.com/episodes/multitenancy-with-apartment)

## Config

The following config options should be set up in a Rails initializer such as:

    config/initializers/apartment.rb

To set config options, add this to your initializer:

```ruby
Apartment.configure do |config|
  # set your options (described below) here
end
```

### Skip tenant schema check

This is configurable by setting: `tenant_presence_check`. It defaults to true
in order to maintain the original gem behavior. This is only checked when using one of the PostgreSQL adapters.
The original gem behavior, when running `switch` would look for the existence of the schema before switching. This adds an extra query on every context switch. While in the default simple scenarios this is a valid check, in high volume platforms this adds some unnecessary overhead which can be detected in some other ways on the application level.

Setting this configuration value to `false` will disable the schema presence check before trying to switch the context.

```ruby
Apartment.configure do |config|
  tenant_presence_check = false
end
```

### Excluding models

If you have some models that should always access the 'public' tenant, you can specify this by configuring Apartment using `Apartment.configure`. This will yield a config object for you. You can set excluded models like so:

```ruby
config.excluded_models = ["User", "Company"]        # these models will not be multi-tenanted, but remain in the global (public) namespace
```

Note that a string representation of the model name is now the standard so that models are properly constantized when reloaded in development

Rails will always access the 'public' tenant when accessing these models, but note that tables will be created in all schemas. This may not be ideal, but its done this way because otherwise rails wouldn't be able to properly generate the schema.rb file.

> **NOTE - Many-To-Many Excluded Models:**
> Since model exclusions must come from referencing a real ActiveRecord model, `has_and_belongs_to_many` is NOT supported. In order to achieve a many-to-many relationship for excluded models, you MUST use `has_many :through`. This way you can reference the join model in the excluded models configuration.

### Postgresql Schemas

#### Alternative: Creating new schemas by using raw SQL dumps

Apartment can be forced to use raw SQL dumps insted of `schema.rb` for creating new schemas. Use this when you are using some extra features in postgres that can't be represented in `schema.rb`, like materialized views etc.

This only applies while using postgres adapter and `config.use_schemas` is set to `true`.
(Note: this option doesn't use `db/structure.sql`, it creates SQL dump by executing `pg_dump`)

Enable this option with:

```ruby
config.use_sql = true
```

### Providing a Different default_tenant

By default, ActiveRecord will use `"$user", public` as the default `schema_search_path`. This can be modified if you wish to use a different default schema be setting:

```ruby
config.default_tenant = "some_other_schema"
```

With that set, all excluded models will use this schema as the table name prefix instead of `public` and `reset` on `Apartment::Tenant` will return to this schema as well.

### Persistent Schemas

Apartment will normally just switch the `schema_search_path` whole hog to the one passed in. This can lead to problems if you want other schemas to always be searched as well. Enter `persistent_schemas`. You can configure a list of other schemas that will always remain in the search path, while the default gets swapped out:

```ruby
config.persistent_schemas = ['some', 'other', 'schemas']
```

### Installing Extensions into Persistent Schemas

Persistent Schemas have numerous useful applications.  [Hstore](http://www.postgresql.org/docs/9.1/static/hstore.html), for instance, is a popular storage engine for Postgresql. In order to use extensions such as Hstore, you have to install it to a specific schema and have that always in the `schema_search_path`.

When using extensions, keep in mind:
* Extensions can only be installed into one schema per database, so we will want to install it into a schema that is always available in the `schema_search_path`
* The schema and extension need to be created in the database *before* they are referenced in migrations, database.yml or apartment.
* There does not seem to be a way to create the schema and extension using standard rails migrations.
* Rails db:test:prepare deletes and recreates the database, so it needs to be easy for the extension schema to be recreated here.

#### 1. Ensure the extensions schema is created when the database is created

```ruby
# lib/tasks/db_enhancements.rake

####### Important information ####################
# This file is used to setup a shared extensions #
# within a dedicated schema. This gives us the   #
# advantage of only needing to enable extensions #
# in one place.                                  #
#                                                #
# This task should be run AFTER db:create but    #
# BEFORE db:migrate.                             #
##################################################

namespace :db do
  desc 'Also create shared_extensions Schema'
  task :extensions => :environment  do
    # Create Schema
    ActiveRecord::Base.connection.execute 'CREATE SCHEMA IF NOT EXISTS shared_extensions;'
    # Enable Hstore
    ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS HSTORE SCHEMA shared_extensions;'
    # Enable UUID-OSSP
    ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA shared_extensions;'
    # Grant usage to public
    ActiveRecord::Base.connection.execute 'GRANT usage ON SCHEMA shared_extensions to public;'
  end
end

Rake::Task["db:create"].enhance do
  Rake::Task["db:extensions"].invoke
end

Rake::Task["db:test:purge"].enhance do
  Rake::Task["db:extensions"].invoke
end
```

#### 2. Ensure the schema is in Rails' default connection

Next, your `database.yml` file must mimic what you've set for your default and persistent schemas in Apartment. When you run migrations with Rails, it won't know about the extensions schema because Apartment isn't injected into the default connection, it's done on a per-request basis, therefore Rails doesn't know about `hstore` or `uuid-ossp` during migrations.  To do so, add the following to your `database.yml` for all environments

```yaml
# database.yml
...
adapter: postgresql
schema_search_path: "public,shared_extensions"
...
```

This would be for a config with `default_tenant` set to `public` and `persistent_schemas` set to `['shared_extensions']`. **Note**: This only works on Heroku with [Rails 4.1+](https://devcenter.heroku.com/changelog-items/426). For apps that use older Rails versions hosted on Heroku, the only way to properly setup is to start with a fresh PostgreSQL instance:

1. Append `?schema_search_path=public,hstore` to your `DATABASE_URL` environment variable, by this you don't have to revise the `database.yml` file (which is impossible since Heroku regenerates a completely different and immutable `database.yml` of its own on each deploy)
2. Run `heroku pg:psql` from your command line
3. And then `DROP EXTENSION hstore;` (**Note:** This will drop all columns that use `hstore` type, so proceed with caution; only do this with a fresh PostgreSQL instance)
4. Next: `CREATE SCHEMA IF NOT EXISTS hstore;`
5. Finally: `CREATE EXTENSION IF NOT EXISTS hstore SCHEMA hstore;` and hit enter (`\q` to exit)

To double check, login to the console of your Heroku app and see if `Apartment.connection.schema_search_path` is `public,hstore`

#### 3. Ensure the schema is in the apartment config

```ruby
# config/initializers/apartment.rb
...
config.persistent_schemas = ['shared_extensions']
...
```

#### Alternative: Creating schema by default

Another way that we've successfully configured hstore for our applications is to add it into the
postgresql template1 database so that every tenant that gets created has it by default.

One caveat with this approach is that it can interfere with other projects in development using the same extensions and template, but not using apartment with this approach.

You can do so using a command like so

```bash
psql -U postgres -d template1 -c "CREATE SCHEMA shared_extensions AUTHORIZATION some_username;"
psql -U postgres -d template1 -c "CREATE EXTENSION IF NOT EXISTS hstore SCHEMA shared_extensions;"
```

The *ideal* setup would actually be to install `hstore` into the `public` schema and leave the public
schema in the `search_path` at all times. We won't be able to do this though until public doesn't
also contain the tenanted tables, which is an open issue with no real milestone to be completed.
Happy to accept PR's on the matter.

### Managing Migrations

In order to migrate all of your tenants (or postgresql schemas) you need to provide a list
of dbs to Apartment. You can make this dynamic by providing a Proc object to be called on migrations.
This object should yield an array of string representing each tenant name. Example:

```ruby
# Dynamically get tenant names to migrate
config.tenant_names = lambda{ Customer.pluck(:tenant_name) }

# Use a static list of tenant names for migrate
config.tenant_names = ['tenant1', 'tenant2']
```

You can then migrate your tenants using the normal rake task:

```ruby
rake db:migrate
```

This just invokes `Apartment::Tenant.migrate(#{tenant_name})` for each tenant name supplied
from `Apartment.tenant_names`

Note that you can disable the default migrating of all tenants with `db:migrate` by setting
`Apartment.db_migrate_tenants = false` in your `Rakefile`. Note this must be done
*before* the rake tasks are loaded. ie. before `YourApp::Application.load_tasks` is called

#### Parallel Migrations

Apartment supports parallelizing migrations into multiple threads when
you have a large number of tenants. By default, parallel migrations is
turned off. You can enable this by setting `parallel_migration_threads` to
the number of threads you want to use in your initializer.

Keep in mind that because migrations are going to access the database,
the number of threads indicated here should be less than the pool size
that Rails will use to connect to your database.

### Handling Environments

By default, when not using postgresql schemas, Apartment will prepend the environment to the tenant name
to ensure there is no conflict between your environments. This is mainly for the benefit of your development
and test environments. If you wish to turn this option off in production, you could do something like:

```ruby
config.prepend_environment = !Rails.env.production?
```

## Tenants on different servers

You can store your tenants in different databases on one or more servers.
To do it, specify your `tenant_names` as a hash, keys being the actual tenant names,
values being a hash with the database configuration to use.

Example:

```ruby
config.with_multi_server_setup = true
config.tenant_names = {
  'tenant1' => {
    adapter: 'postgresql',
    host: 'some_server',
    port: 5555,
    database: 'postgres' # this is not the name of the tenant's db
                         # but the name of the database to connect to, before creating the tenant's db
                         # mandatory in postgresql
  }
}
# or using a lambda:
config.tenant_names = lambda do
  Tenant.all.each_with_object({}) do |tenant, hash|
    hash[tenant.name] = tenant.db_configuration
  end
end
```

## Background workers

Both these gems have been forked as a side consequence of having a new gem name.
You can use them exactly as you were using before. They are, just like this one
a drop-in replacement.

See [apartment-sidekiq](https://github.com/rails-on-services/apartment-sidekiq)
or [apartment-activejob](https://github.com/rails-on-services/apartment-activejob).

## Callbacks

You can execute callbacks when switching between tenants or creating a new one, Apartment provides the following callbacks:

- before_create
- after_create
- before_switch
- after_switch

You can register a callback using [ActiveSupport::Callbacks](https://api.rubyonrails.org/classes/ActiveSupport/Callbacks.html) the following way:

```ruby
require 'apartment/adapters/abstract_adapter'

module Apartment
  module Adapters
    class AbstractAdapter
      set_callback :switch, :before do |object|
        ...
      end
    end
  end
end
```

## Running rails console without a connection

Before this fork, running rails with the gem installed would connect to the database
which is different than the default behavior. To disable this initial
connection, just run with `APARTMENT_DISABLE_INIT` set to something:

```shell
$ APARTMENT_DISABLE_INIT=true DATABASE_URL=postgresql://localhost:1234/buk_development bin/rails runner 'puts 1'
# 1
```

## Contributing

* In both `spec/dummy/config` and `spec/config`, you will see `database.yml.sample` files
  * Copy them into the same directory but with the name `database.yml`
  * Edit them to fit your own settings
* Rake tasks (see the Rakefile) will help you setup your dbs necessary to run tests
* Please issue pull requests to the `development` branch. All development happens here, master is used for releases.
* Ensure that your code is accompanied with tests. No code will be merged without tests

* If you're looking to help, check out the TODO file for some upcoming changes I'd like to implement in Apartment.

### Running bundle install

mysql2 gem in some cases fails to install.
If you face problems running bundle install in OSX, try installing the gem running:

`gem install mysql2 -v '0.5.3' -- --with-ldflags=-L/usr/local/opt/openssl/lib --with-cppflags=-I/usr/local/opt/openssl/include`

## License

Apartment is released under the [MIT License](http://www.opensource.org/licenses/MIT).
