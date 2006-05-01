# class: CGI::Persist::Cache
#
# A Cache::File implementation of CGI::Persist
#
package CGI::Persist::Cache;

BEGIN {
  $CGI::Persist::Cache::VERSION = '2.41';
}

use strict;
no strict 'refs';

use base qw(CGI::Persist);
use Cache::File;

# modules accessors
use Class::AccessorMaker::Private {
  root  => '/tmp',
  umask => 077,
  cache => "",
}, "no_new";

sub init {
  my ( $self ) = @_;

  $self->openDB;
  $self->SUPER::init;
}

# method: openDB
#
# Called by Persist::init to start talking to the Database.
#
# Put's a new cache object in $self->cache;
#
sub openDB {
  die ("Only CGI::Persist can openDB\n")
    if !( caller =~ /Persist/ );

  my ($self) = @_;

  return if ref($self->cache) =~ /cache::file/i;

  if ( $self->root =~ /\.\// ) {
    $self->root($ENV{PWD} . "/" . $self->root);
  }

  if ( !-d $self->root ) {
    $self->errorLog("Storage root has gone away");
    return undef;
  }

  $self->cache( Cache::File->new( cache_root      => $self->root,
				  cache_umask     => $self->umask,
				  lock_level      => Cache::File::LOCK_LOCAL(),
				  default_expires => $self->sessionTime . " sec",
				) 
	      );

  return 1;
}

# method: closeDB
#
# Called by Persist::init to close the DB.
#
# Put's undef in $self->cache
#
sub closeDB {
  my ( $self ) = @_;

  $self->cache(undef);
}

# method: get( $ID )
#
# Returns the entry for $ID. $self->ID is used by default.
#
sub get {
  my ($self, $ID) = @_;
  $ID ||= $self->ID;

  if ( my $frozen = $self->cache->get( $ID ) ) {
    $self->deserialize($frozen);
  }
}

# method: store
#
# Stores the present object back into the DB.
#
sub store {
  my ($self, $create) = @_;

  my $ID = $self->ID;
  $self->log("store $ID");

  $self->filterSessionData() unless $create;
  my $frozen = $self->serialize();

  if ( $frozen && UNIVERSAL::can($self->cache, "set") ) {
    $self->cache->set( $ID => $frozen );

  } else {
    $self->errorLog("Cant store into unopened DB");

  }

  $self->cleanUp;
}

# method: clean
#
# Vacuuming the cache.
#
sub clean {
  my ( $self ) = @_;

  my $count = $self->cache->count;
  $self->cache->purge;
  $self->log("Removed " . ($count-$self->cache->count) . "/$count entries from cache");
}

sub DESTROY {
  my ( $self ) = @_;

  $self->store;
  $self->closeDB;
}

1;

__END__

=pod

=head1 NAME

CGI::Persist::Cache - CGI::Persist using Cache::File

=head1 DESCRIPTION

CGI::Persist::Cache is the Cache::File-based front end to CGI::Persist

=head1 SYNOPSIS

  use strict; #|| die!
  my $p = CGI::Persist::Cache->new( root => "Foo",
                                    umask => 002,
                                    sessionTime => 900,
				 );

  # add a parameter to the data.
  $p->param(-name => "Veggie", -value = "TRUE");

  # read a parameter from the data.
  $id = $p->param('id') || $p->ID;

  # store something completely else
  $p->data( MyName => "Hartog C. de Mik",
            key => "0294202049522095",
          );

  # check if the button was pushed.
  if ( $cgi->gotSubmit("the_button") ) {
    # ...
  }

  # check is the param is NOT this requested now
  if ( $cgi->param("the_param") && !defined $cgi->currentParam("the_param") ) {
    # ...
  }

=head1 ACCESSOR METHODS

=over 4

=item * root

Specify the /path/to for you tmp-files. Defaults to /tmp. 
If you use "../" in your root() CGI::Persist::File causes a die.

=item * umask

Specify the umask for Cache::File. 077 by default.

=back

=head1 SEE ALSO

CGI(3), CGI::Persist

=head1 AUTHOR

Hartog C. de Mik, hartog@2organize.com

=cut
