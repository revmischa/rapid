package Rapid;

use Moose;
use Rapid::Config;
use Rapid::LazySchema;
use Rapid::Logger;
use Path::Class qw(file dir);
use Class::MOP;
use FindBin;

# our app name should be set in $Rapid::APP_NAME
our $APP_NAME;

# exported vars
our ($config, $schema, $log);
our $_config;

# set up exports
use Exporter::Tidy
    default => [],
    _map => {
        '$config' => \$config,
        '$schema' => \$schema,
        '$log' => \$log,
    };

setup();

sub setup {
    my $package = __PACKAGE__;
    die "Please define \$${package}::APP_NAME before extending $package"
        unless $APP_NAME;

    # load config
    $_config = Rapid::Config->new(
        app_name => $APP_NAME,
        app_root => find_app_root(),
    );
    $config = $_config->get;

    # load schema
    $schema = Rapid::LazySchema->new(
        config_obj => $_config,
    );

    # load logger
    my $log_level = $config->{log_level};
    my %log_opts;
    $log_opts{log_level} = $log_level if defined $log_level;
    $log = Rapid::Logger->new(%log_opts);
}

# traverses parent directories of the current script being run,
# looking for a directory containing '.app_root'
sub find_app_root {
    my ($class) = @_;

    # traverse upwards until we find '.app_root'
    my $root = dir($FindBin::RealBin);
    while ($root && ! -e $root->file('.app_root')) {
        if ($root eq $root->parent) {
            # we are at /
            # .app_root was not found
            die qq/Failed to locate application root.
You must have an '.app_root' file located in the root directory of your application.
Current search path: $FindBin::RealBin/;
        }
        
        $root = $root->parent;
    }

    return $root;
}

1;
