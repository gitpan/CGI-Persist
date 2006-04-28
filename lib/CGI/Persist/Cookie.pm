# class: CGI::Persist::Cookie
#
# A Cookie implementation of CGI::Persist
#
package CGI::Persist::Cookie;

BEGIN {
  $CGI::Persist::Cookie::VERSION = '0.1';
}

use strict;
no strict 'refs';

use base qw(CGI::Persist);
use CGI::Cookie;

# modules accessors
use Class::AccessorMaker::Private {
  _jar           => {},
  _cookie => [],

  path   => "/",
  domain => "",
  secure => 0,
}, "no_new";

sub init {
  my ( $self ) = @_;

  # fetch existing cookies.
  my %cookies = fetch CGI::Cookie;
  $self->_jar( \%cookies );

  # get the ID from the jar.
  exists $self->_jar->{'_session_id'} && ( my $id = $self->_jar->{'_session_id'}->value );

  $self->SUPER::param( -name => "ID",
		       -value => $id,
		     );

  $self->SUPER::init;

  # make the first cookie to remember.
  $self->_cookie( [ new CGI::Cookie( -name  => "_session_id",
				     -value => $self->ID,
				     $self->cookieAttributes,
				   ) ] );

  $self->store if ( $self->firstRun );
}

sub data {
  my $self = shift;

  my ($tag, $val);

  if ( $#_ > 0 && $#_ =~ /[13579]$/) {
    # set values
    while(($tag, $val) = splice(@_,0,2)) {
      next if ( $tag ne "REMOTE_ADDR" && $tag ne "HTTP_USER_AGENT" );

      $self->SUPER::data( $tag => $val );
    }

  } else {
    return $self->SUPER::data(@_);

  }
}

# method: get( $ID )
#
# Returns the entry for $ID. $self->ID is used by default.
#
sub get {
  my ($self, $ID) = @_;
  $ID ||= $self->ID;

  ( my $cookie = $self->_jar->{$ID} ) || return undef;

  if ( my $frozen = $cookie->value ) {
    $self->deserialize( $frozen );

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

  if ( $frozen ) {
    my @cookies = @{ $self->_cookie };
    my $updated = 0;

    foreach my $c ( @cookies ) {
      if ( $c->name eq $ID ) {
	$c->value => $frozen;
	$updated = 1;
	last;
      }
    }

    if ( $updated ) {
      $self->_cookie( [ @cookies ] );

    } else {
      $self->_cookie( [ @{$self->_cookie},
			new CGI::Cookie( -name  => $ID,
					 -value => $frozen,
					 $self->cookieAttributes,
				       ),
		      ] );
    }
    
  } else {
    $self->errorLog("Nothing to store...");

  }

  $self->cleanUp;
}

sub cookieAttributes {
  my ( $self ) = @_;

  return ( -expires => "+" . $self->sessionTime . "s",
	   -path    => $self->path,
	   -domain  => $self->domain,
	   -secure  => ( $self->secure ? 1 : 0 ),
	 );
}

sub persistCookies {
  my ( $self ) = @_;
  $self->store;

  return @{$self->_cookie}
}

sub DESTROY {
  my ( $self ) = @_;

  $self->store;
}

1;

__END__

=pod

=head1 NAME

CGI::Persist::Cookie

=head1 DESCRIPTION

CGI::Persist::Cookie is a cookie based front end to CGI::Persist with
no data-footprint on the server. Everything is stored into the user's
webbrowser.

This is not for fun and _only_ usefull when you have only few fields
to remember and don't want the hassle of putting those fields into
your HTML / template.

CGI::Persist::Cookie disables the data interface from CGI::Persist, to
make sure the data serialized into the users browser is kept small.

=head1 SYNOPSIS

  my $cgi = CGI::Persist::Cookie->new( path => "/cgi",
                                       domain => "www.2organize.com",
                                       secure => 0,
                                       sessionTime => 900,
                                     );

  # add a parameter to the data.
  $cgi->param(-name => "Veggie", -value = "TRUE");

  # read a parameter from the data.
  $id = $cgi->param('id') || $cgi->ID;

  # check if the button was pushed.
  if ( $cgi->gotSubmit("the_button") ) {
    # ...
  }

  # check is the param is NOT this requested now
  if ( $cgi->param("the_param") && !defined $cgi->currentParam("the_param") ) {
    # ...
  }

  # and now, to make sure it keeps on working, print a cookied-header.
  print $cgi->header( -cookie => [ @all_my_cookies, $cgi->persistCookies ] );

=head1 ACCESSOR METHODS

=over 4

=item * path

=item * domain

=item * secure

See CGI::Cookie for more information.

=back

=head1 CAVEATS


=head1 SEE ALSO

CGI(3), CGI::Persist

=head1 AUTHOR

Hartog C. de Mik, hartog@2organize.com

=cut
