#!/usr/bin/env perl 

use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use JSON;
use Getopt::Long

my %opts = ();
GetOptions(
					 'action=s'  => \$opts{action},
					 'file=s'    => \$opts{file},
					 'geolat=s'  => \$opts{geolat},
					 'geolong=s' => \$opts{geolong},
					 'vcount=s'  => \$opts{vcount},
					 'vid=s'     => \$opts{vid},
          );

my $rc_file     = "$ENV{HOME}/.4squatterrc";
my $config      = &getConfig( $rc_file );

my %lwp_opts = (
								agent => $config->{esquare_agent}, 
								timeout => 10,
							 );

my $debug = 0;

# parse the options and determine the action that we're going to take
if ( $opts{action} eq '' ) {
	&printUsage("no action specified");
	exit;
} else { $opts{'action'} =~ tr/A-Z/a-z/; } 


# parse the various CLI opts
if ($opts{action} eq "disp_venues") {
	if ($opts{geolat} eq "" || $opts{geolong} eq "" ) {
		&printUsage("missing coordinates (geolat or geolong)");
		exit;
	} else {
		my $ua =  LWP::UserAgent->new(%lwp_opts);
		&displayVenues($ua, $opts{geolat}, $opts{geolong} );
		exit;
	}

} elsif ($opts{action} eq "checkin") {
	# check-in at a single venue - vid is the only required element, if we have
	# the lat/long it would be good to include it too
	if ( $opts{vid} eq '' ) {
		&printUsage("missing venue id (vid)");
		exit;
	}

	my $ua =  LWP::UserAgent->new(%lwp_opts);

	if ($opts{geolat} ne '' && $opts{geolong} ne '') {
		my $checkin = &esquare_checkin( $ua, $opts{vid}, $opts{geolat}, $opts{geolong} );
		print "$checkin\n";
		exit;
	} else {
		my $checkin = &esquare_checkin( $ua, $opts{vid} );
		print "$checkin\n";
		exit;
	}

} elsif ($opts{'action'} eq "checkin-batch") {
	#my $ua =  LWP::UserAgent->new(%lwp_opts);
	$config->{esquare_vfile} = $opts{vfile} if ($opts{vfile} ne '');
	&checkinBatchVenues($config->{esquare_vfile});
	exit;
}



# 
sub checkinBatchVenues() {
	my ($file) = @_;

	my $ua =  LWP::UserAgent->new(%lwp_opts);

	my @venues = &loadVenues($file);
	foreach my $venue (@venues) {
		$venue =~ s/\r|\n//g;
		my ($vid, $name, $geolat, $geolong) = split ("\t", $venue);
			
		my $checkin = &esquare_checkin($ua, $vid, $geolat, $geolong, $name);;
		print "$checkin\n";
	}
}


sub esquare_checkin() {
	my ($ua, $vid, $geolat, $geolong, $name) = @_;

	my $checkin_url = "http://api.foursquare.com/v1/checkin.json";
	my $form_params = [ vid => $vid ];

	push @{$form_params}, geolat => $geolat 	if ($geolat ne "");
	push @{$form_params}, geolong => $geolong if ($geolong ne "");

	my $req = HTTP::Request::Common::POST $checkin_url, [ vid => $vid ];
	$req->authorization_basic( $config->{esquare_user}, $config->{esquare_pass} ); 
	
	my $ua_resp = $ua->request($req);
	my $json = new JSON;

	my $resp_mesg = "";
	if ($ua_resp->is_success) {
		my $json_resp = $json->decode( $ua_resp->decoded_content );
		$resp_mesg = "checkin success: $vid - $name";
	}	else { 
		$resp_mesg = "checkin error: $vid - $name - " . $ua_resp->status_line;
		#die $ua_resp->status_line; 
	}
	
	return $resp_mesg;
}



sub displayVenues() {
	# if there's no venue file and the user has provided the coords, do the
	# active lookup online

	my ($ua, $geolat, $geolong) = @_;

	my $venue_url = "http://api.foursquare.com:80/v1/venues.json";

	$venue_url .= "?geolat=$geolat";
	$venue_url .= "&geolong=$geolong";

	$ua->credentials($config->{esquare_host}, $config->{esquare_rlm},
									 $config->{esquare_user}, $config->{esquare_pass},);

	if ($opts{vcount} ne '') {
		if ( $opts{vcount} !~ /\d+/) {
			&printUsage("invalid --vcount value");
			exit;
		}
		$venue_url .= "&l=$opts{vcount}";
	}

	my $ua_resp = $ua->get($venue_url);
	my $json = new JSON;
	
	if ($ua_resp->is_success) {
		print $ua_resp->decoded_content if $debug >= 2;  # logging info
		my $json_resp = $json->decode( $ua_resp->decoded_content );

		# this indexes to the venue in the structure:
		#    $json_resp->{'groups'}->[0]->{venues}->[0]->{name};
		#
		# convert to the appropriate hashref by dereferencing the array
		# @{$json_resp->{'groups'}->[0]->{'venues'}}

		print "# vid\tvenue name\t\tgeolat\tgeolong\n";
		print "#" . '-' x 69 . "\n";
		foreach my $venue ( @{$json_resp->{'groups'}->[0]->{'venues'}} ) {
			print $venue->{'id'} . "\t" . $venue->{'name'} . "\t" .
				$venue->{geolat}. "\t" . $venue->{geolong} . "\n"
		}
	}
	else { die $ua_resp->status_line; }
	
	return;
}




#---------------------------------------------------------------------
# misc. helper functions



# print the usage information - terse
sub printUsage() {
	my ($message) = @_;
	print STDERR $message . "\n";

	print STDERR <<EOF;
usage: foursquatter.pl

you need to set some options and variables. check the code to see what you
need to setup here.  


foursquare.pl --action=<action>

valid actions: 
	 
checkin 
 --vid=

example: 
   foursquatter.pl --action=checkin --vid=XXXX

checkin-batch  
 [--file=filename] 

example: 
   foursquatter.pl --action=checkin-batch

disp_venues
 --geolat=s --geolong=s [--vcount=#]

example: 
   foursquatter.pl --action=disp_venues --geolat=xx.xxx --geolong=yy.yyy \
   --vcount=NN


EOF

	return;
}

# get the rc config file elements
sub getConfig() {
	my ($file) = @_;

	my %config = ();
	open(INFILE, $file) || die "error opening: $file";
	while (<INFILE>) {	
		next if /^#/;  # skip comments
		my ($key, $value) = /(.*)\s+\=\s+[\"|\'](.*)[\"|\']/;
		$key =~ s/ //;  # rip out any white space from the key
		$config{$key} = $value;
	}
	close(INFILE);

	return \%config;
}

# load the venues file
sub loadVenues() {
	my ($file) = @_;

	my @venues = ();

	open(VENUES, $file) || die "error opening venues file: $file";
	while (<VENUES>) {
		next if /^#/;  # skip comments
		push(@venues, $_);
	}
	close(VENUES);

	return @venues;
}

