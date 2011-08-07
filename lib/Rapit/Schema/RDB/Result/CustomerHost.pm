package Rapit::Schema::RDB::Result::CustomerHost;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
extends 'DBIx::Class::Core';

__PACKAGE__->load_components("InflateColumn::DateTime");
__PACKAGE__->table("customer_host");
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "customer_host_id_seq",
  },
  "customer",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "created",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint(
  "customer_host_customer_hostname_key",
  ["customer", "hostname"],
);
__PACKAGE__->belongs_to(
  "customer",
  "Rapit::Schema::RDB::Result::Customer",
  { id => "customer" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);
__PACKAGE__->has_many(
  "registries",
  "Rapit::Schema::RDB::Result::Registry",
  { "foreign.customer_host" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-08-06 17:15:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:c8V8CKJbt/QC31MLN7GjgA


# You can replace this text with custom content, and it will be preserved on regeneration
1;


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
