#!/usr/bin/env perl

package Rapit::API::Server::Async::EchoTest;

use Moose;
extends 'Rapit::API::Server::Async';

before 'run' => sub {
    my ($self) = @_;
    
    $self->register_callbacks(
        echo => \&echo,
    );
};

sub echo {
    my ($self, $msg, $conn) = @_;

    $conn->push($msg->command, {
        %{ $msg->params },
        echo => 1,
    })
}

##

package EchoTestServer;

use Moose;
use Bread::Board;

extends 'Rapit::Container';

has '+name' => ( default => 'EchoTestServer' );

sub BUILD {
    my ($self) = @_;

    $self->build_container;
    
    $self->fetch('/API/Server')->add_service(
        Bread::Board::ConstructorInjection->new(
            name         => 'EchoTest',
            class        => 'Rapit::API::Server::Async::EchoTest',
            dependencies => {
                port => depends_on('/API/port'),
            },
        ),
    );
}

##

package main;

use Moose;
use Test::More tests => 3;
use Bread::Board;
use AnyEvent;
use Rapit::Common;
use FindBin;

my %test_customer = (
    name => 'test customer',
    key => 'fakekey',
);

# construct server
my $c = EchoTestServer->new(
    app_root => "$FindBin::Bin/..",
);

# fetch DB schema
my $schema = Rapit::Common->schema;
my $customer_rs = $schema->resultset('Customer');

# make sure our test account doesn't exist yet
$customer_rs->search(\%test_customer)->delete_all;

# fetch server and client
my $server = $c->fetch('/API/Server/EchoTest')->get;
my $client = $c->fetch('API/Client/Async')->get;

# run the server
$server->run;

my $cv = AE::cv;

$client->register_callback(logged_in => sub { $cv->send });

# create a client, connect to server
expect_error(qr/No login_key/i, "Got no login key error");

# set login_key this time
$client->client_key('fakekey');
expect_error(qr/Invalid login_key/i, "Got invalid key error");

# done with this test
#$cv = AE::cv;

# create a valid login
my $customer = $customer_rs->create(\%test_customer);

# terminate busyloop when login complete
$client->register_callback(logged_in => sub { warn "logged in!"; $cv->send });

$client->connect;

$cv->recv;
ok($client->is_logged_in, "Logged in");

$client->disconnect;

$customer->delete;
 
undef $client;
undef $server;
$c->shutdown;

done_testing();

sub expect_error {
    my ($err, $test) = @_;
    
    $client->clear_callbacks('disconnect');
    $client->clear_callbacks('error');

    my $err_handler = sub {
        my ($self, $msg) = @_;
        my $error_message = $msg->error_message;
        like($error_message, $err, $test);
        $cv->send;
    };
    
    $client->register_callbacks(
        error => $err_handler,
        disconnect => $err_handler,
    );
    $cv = AE::cv;
    $client->connect;
    $cv->recv;

    $client->clear_callbacks('disconnect');
    $client->clear_callbacks('error');

    # restore default handlers
    $client->_register_default_handlers;
}