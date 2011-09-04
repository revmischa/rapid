package Rapit::API::Client;

use Moose::Role;
    with 'Rapit::API';

use namespace::autoclean;

has 'client_key' => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    builder => '_build_client_key',
);

sub _build_client_key {
    my ($self) = @_;
    
    return $self->config->{client_key}
        or die "client_key is not configured";
}

1;