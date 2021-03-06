package Rapid::API::Server::Connection;

use Moose;
use namespace::autoclean;
use Data::Dumper;
use Rapid::API::Message;
use Time::HiRes;
use Rapid::UUID;
use Carp qw/croak/;

with 'Rapid::API::Messaging';

has 'host' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

has 'port' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has 'id' => (
    is => 'rw',
    isa => 'Str',
    lazy_build => 1,
);

has 'last_ping_time' => (
    is => 'rw',
    isa => 'Num',
);

has 'ping_time' => (
    is => 'rw',
    isa => 'Num',
);

has 'finish' => (
    is => 'rw',
    isa => 'CodeRef',
    required => 1,
);

has 'fh' => (
    is => 'rw',
    required => 1,
);

has 'server' => (
    is => 'rw',
    does => 'Rapid::API',
    handles => [ qw/ log handle_message
                     schema dispatch / ],
    required => 1,
);

has 'customer_host' => (
    is => 'rw',
    isa => 'Rapid::Schema::RDB::Result::CustomerHost',
);

sub _build_id { Rapid::UUID->create }

sub is_logged_in {
    my ($self) = @_;

    return $self->customer ? 1 : 0;
}

sub customer {
    my ($self) = @_;

    return unless $self->customer_host;
    return $self->customer_host->customer;
}

sub hostname {
    my ($self) = @_;

    return unless $self->customer_host;
    return $self->customer_host->hostname;
}

sub create_handle {
    my ($self) = @_;
    
    my $fh = $self->fh;
    my $host = $self->host;
    my $port = $self->port;
    
    my $h; $h = new AnyEvent::Handle
        fh => $fh,
        on_error => sub {
            my (undef, $fatal, $msg) = @_;
        
            if ($fatal) {
                $self->log->warn("[$host:$port] fatal connection error: $msg");
            } else {
                $self->log->debug("[$host:$port] non-fatal connection error: $msg");
            }
        
            $self->finish->();
            $h->destroy;
        },
        on_eof => sub {
            $self->log->debug("[$host:$port] has disconnected");
            $self->finish->();
            $h->destroy;
        },
        on_read => sub {
            $h->push_read(json => sub {
                my (undef, $data) = @_;
                $self->log->trace(Dumper($data));
                $self->got_message($self, $data);
            });
        };

    $self->h($h);
}

sub got_message {
    my ($self, $conn, $msg_hash) = @_;
    
    return $conn->push_error("Empty message")
        unless $msg_hash;

    # deserialize into Message instance
    my $msg = Rapid::API::Message->deserialize($msg_hash, $conn)
        or return $conn->push_error("Failed to unpack message");
        
    # message must have a command
    return $conn->push_error("Message missing command")
        unless $msg->command;

    # client returned error?
    if ($msg->is_error) {
        $self->log->error("Got error from client: " . $msg->error_message);
        return;
    }

    my $cmd = $msg->command;

    if ($cmd eq 'pong') {
        my $last_ping = $self->last_ping_time;
        my $ping = Time::HiRes::time() - $self->last_ping_time;
        unless ($last_ping) {
            $conn->warn("Got pong but no ping recorded");
        }

        $self->log->debug(sprintf("client ping: %0.3fms", $ping));
        $self->ping_time($ping);
        return 1;
    }
    
    # check if they are logging in
    if ($cmd eq 'login') {
        my $key = $msg->params->{login_key}
            or return $conn->push_error("No login_key specified");
            
        my $hostname = $msg->params->{host_name}
            or return $conn->push_error("No host_name specified");
            
        # attempt to log in customer
        my $cust = $self->schema->resultset('Customer')->find({ 'key' => $key });
        if (! $cust) {
            return $conn->push_error("Invalid login_key '$key'");
        }
            
        # find/create customer_host
        my $customer_host = $self->schema->resultset('CustomerHost')->find_or_create({
            customer => $cust->id,
            hostname => $hostname,
        });
        $customer_host->update({ updated => \ 'NOW()' });
            
        $conn->customer_host($customer_host);
        $self->log->info("Customer " . $cust->name . " logged in from $hostname");
        return $self->push('logged_in', { customer_name => $cust->name });
    }
    
    # must be logged in to go further
    return $conn->push_error("Not logged in")
        unless $conn->customer_host && $conn->customer;
        
    # client is authenticated
    
    # call appropriate method
    my $ok = eval {
        $self->dispatch($msg, $conn);
    };
    
    unless (defined $ok) {
        my $err = $@ || '(unknown error)';
        $self->log->error("Caught error handling $cmd command: $err");
        return $self->push_error("Internal server error");
    }
}

sub DEMOLISH {
    my ($self) = @_;
    
    $self->log->debug("Connection shut down") if $self->server;
}

__PACKAGE__->meta->make_immutable;
