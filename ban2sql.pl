#!/usr/bin/perl

#######################################################################
# Ban2SQL v2.0 by Kotori <kotori@greenskin.hopto.org>                 #
#  When this application is called via Fail2Ban, it places the ban,   #
#   and geo location data in a specified database for easy retrieval. #
#                                                                     #
#  Inspired by Fail2SQL v1.0 by Jordan Tomkinson <jordan@moodle.com>  #
#                                                                     #
# Requirements:                                                       #
#  Fail2Ban, MySQL, Perl, GeoIP perl lib,                             #
#  DBI perl lib, LWP::Simple perl lib,                                #
#  Archive::Extract perl lib, File::Copy perl lib                     #
#                                                                     #
# Ban2SQL is free software; you can redistribute it and/or modify     #
#  it under the terms of the GNU General Public License as published  #
#  by the Free Software Foundation; either version 2 of the License,  #
#  or (at your option) any later version.                             #
#######################################################################

use strict;
use warnings;

use File::Copy;
use Geo::IP::PurePerl;
use DBI;
use LWP::Simple;
use Archive::Extract;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

#### begin user config ####

# Path to the ban2sql installation
my $home = '/etc/fail2ban/ban2sql';

# Path to the GeoLiteCity.dat database from MaxMind.
my $url = 'http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz';

# Filename to use when extracting. (should be obvious from the url)
my $file = $home . '/GeoLiteCity.dat.gz';

# Filename to use when extracted. (if you are using geolite city, keep this value as is)
my $final = $home . '/GeoLiteCity.dat';

# MySQL variables
my $host = 'localhost';		# hostname of MySQL server.
my $user = 'ban2sql';		# username of the bans database.
my $pw = 'ban2sql';		# password for the bans user.
my $db = 'ban2sql';		# database contains bans table.
my $table = 'ban2sql';		# table containing bans.

#### end user config ####

if (@ARGV ge 1) {
  if ($ARGV[0] eq "-i" ) {
    # This should really only occur if Fail2Ban calls it, however you can also use -i to manually enter in a ban.
    # /etc/fail2ban/ban2sql/ban2sql.pl -i <name> <protocol> <port> <ip>

    my $ban_name = $ARGV[1];
    my $ban_protocol = $ARGV[2];
    my $ban_port = $ARGV[3];
    my $ban_ip = $ARGV[4];
 
    # connect to MySQL database
    my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
      or die "Can't connect to database: $DBI::errstr\n";

    my ($count) = $dbh->selectrow_array("SELECT count FROM `$table` WHERE ip = '$ban_ip'");

    # Ensure this IP doesn't already exist in the database.
    if(defined $count) {
      # if the record already exists, simply update the counter, and last seen time.
      my $query = "UPDATE `$table` SET count=count+1, date_last_seen=NOW() WHERE ip = '$ban_ip'";
      my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;      

      $sth->finish;
    }
    else {
      # Open GeoIP lookup database.
      my $gi = Geo::IP::PurePerl->open( $final, GEOIP_STANDARD )
        or die "Failed to open GeoIP database, check $final";

      # Assign the geo location data into the following variables for ban_ip
      my ($country_code,$country_code3,$country_name,$region,$city,$postal_code,$latitude,$longitude,$metro_code,$area_code) = $gi->get_city_record( $ban_ip );

      # Grab the port number from the service name passed by fail2ban.
      my ($service_name, $service_alias, $service_port, $service_protocol) = getservbyname($ban_port, $ban_protocol);
      
      # Build the query to insert the ban into the database.
      my $query = "INSERT INTO `$table` values ('', '$service_name', '$service_protocol', '$service_port', '$ban_ip', '1', '$longitude', '$latitude','$country_code', '$city, $region -- $country_name', NOW(), NOW())";
      
      # Prepare the query we just built.
      my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
      # Execute the query
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
        
      $sth->finish;
    }

    # Disconnect from the database now that we are done.
    $dbh->disconnect;

  }
  elsif ($ARGV[0] eq "-l") {
    #connect to MySQL database
    my $dbh = DBI->connect("DBI:mysql:database=$db:host=$host", $user, $pw)
      or die "Can't connect to database: $DBI::errstr \n";

    # Prints results
    print "Bans Collected: \n";

    # Pull top 50 bans
    my $query = "SELECT * FROM `$table` ORDER BY count DESC LIMIT 50";
    # my $query = "SELECT * FROM `fail2ban-perl` ORDER BY count DESC LIMIT 50";
    my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
    $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;

    while (my @row = $sth->fetchrow_array()) {
      print "$row[1]($row[3]/$row[2]): $row[4] | Count: $row[5] | Geo: $row[9] | Last Seen: $row[10] | First Seen: $row[11] \n";
    }
    warn "Error: ", $sth->errstr( ), "\n" if $sth->err();

    # Disconnect from the database now that we are done.
    $sth->finish;
    $dbh->disconnect;
  }
  elsif ($ARGV[0] eq "-d" ) {
    # Delete a record from the database.
    my $ip_to_remove = $ARGV[1];

    unless( $ip_to_remove ) {
      print "Proper usage: ./ban2sql.pl -d <IP> \n\n",
            " Example: ./ban2sql.pl -d 192.168.100.15 \n\n";
      die;
    }

    # connect to MySQL database
    my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
      or die "Can't connect to database: $DBI::errstr\n";
    
    # Find the row for matching ip_to_remove
    my $query = "SELECT * FROM `$table` WHERE ip='$ip_to_remove'";
    my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
    $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
    
    while ( my @row = $sth->fetchrow_array() ) {
      print "$sth->{NAME}->[1]\t$sth->{NAME}->[4]\t\t$sth->{NAME}->[5]\t$sth->{NAME}->[9]\t\t\t$sth->{NAME}->[10]\t\t$sth->{NAME}->[11]\n";
      print "$row[1]\t$row[4]\t$row[5]\t$row[9]\t\t$row[10]\t$row[11] \n";
    }
    warn "Error: ", $sth->errstr( ), "\n" if $sth->err();

    print "Are you sure you would like to remove this entry? [y/n]  ";
    chomp( my $choice=<STDIN> );
    if ( $choice eq "y" || $choice eq "Y" ) {
      $query = "DELETE FROM `$table` WHERE id='$ip_to_remove'";
      my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $sth->errstr;
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
    }
    
    # Disconnect from the database now that we are done.
    $sth->finish;
    $dbh->disconnect;
  }   
  elsif ($ARGV[0] eq "-u") {
    # Update the MaxMind database.
    if (-e $file) {
      # you should really backup the db first in case the download fails.
      my $backup_filename = $file . '.bak';
      copy( $file, $backup_filename );
      # Remove the gzip file to save space.
      unlink( $file );
    }

    # Using the LWP's getstore we will retrieve the file from $url and rename it to $file
    getstore ( $url, $file ) or die 'Unable to get $url';

    # Make sure the database actually downloaded, and ungzip it, rename the database to final
    if (-e $file) {
      gunzip $file => $final or die "gunzip failed: $GunzipError\n";
      unlink( $file ) or die "Failure to Remove file: $file";
    }
    else {
      print "Error Downloading new database. \nTry Again in 24Hours. \n";
    }
  }
}
else {
  print "Ban2SQL\n",
        " Usage: ./ban2sql.pl <argument>\n",
        "  -l  : List the last 50 Bans.\n",
        "  -u  : Download the latest MaxMind GeoIP database.\n",
        "  -i  : Insert a new record into the database.\n",
        "  -d  : Remove a record from the database.\n\n",
        " This program comes with ABSOLUTELY NO WARRANTY!\n",
        " This is free software, and you are welcome to redistribute it\n",
        " under certain conditions.\n";
}

exit 0;
