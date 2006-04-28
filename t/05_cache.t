BEGIN {
  $ENV{REQUEST_METHOD}='GET';
  $ENV{HTTP_USER_AGENT} = 'shell';
  $ENV{REMOTE_ADDR} = '127.0.0.1';
}

use Test::More qw(no_plan);

use strict;

use_ok("CGI::Persist::Cache");

SKIP: {
  eval "use Cache::File";

  skip "Cache::File not (propperly) installed, CGI::Persist::Cache will not work", 3 if $@;

  my $cgi = CreateCGI();
  ok( ref($cgi) =~ /cgi::persist::cache/i );
  my $id = $cgi->ID;

  undef $cgi;

  FakeRequest( ID => $id, q => 1, hoi => 1, hoi => 2, hoi => 3 );
  $cgi = CreateCGI();


  foreach ( $cgi->param ) {
    foreach my $p ( $cgi->param($_) ) {
      print "  $_ : $p\n";
    }
  }

  is(join(", ", ( $cgi->currentParam("hoi"))), "1, 2, 3", "Value array currentParam");  
}
  

sub FakeRequest{
  my @all = @_;
  my ($key, $val);
  my $str;

  while (($key, $val, @all ) =  @all) {
    $str .= ( $str ? "&" : "" ) . "$key=$val";
  }

  $ENV{QUERY_STRING}="$str";
  return 1;
}

sub CreateCGI {
  my $stime = shift || 900;

  no CGI::Persist::Cache;
  $INC{'CGI/Persist/Cache.pm'} = '';

  use CGI::Persist::Cache;

  my $p = CGI::Persist::Cache->new( root         => "./tmp/cache",
				    sessionTime  => $stime,
				    logFile      => "./tmp/test.log",
				    errorLogFile => "./tmp/error.log",
				 );

  return($p);
}