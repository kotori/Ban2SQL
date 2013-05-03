#!/usr/bin/perl -Tw

#######################################################################
# Ban2SQL v1.0.3 by Kotori <kotori@greenskin.hopto.org>               #
#  When this application is called via Fail2Ban, it places the ban,   #
#   and geo location data in a specified database for easy retrieval. #
#                                                                     #
#  Inspired by Fail2SQL by Jordan Tomkinson <jordan@moodle.com>       #
#                                                                     #
# Ban2SQL is free software; you can redistribute it and/or modify     #
#  it under the terms of the GNU General Public License as published  #
#  by the Free Software Foundation; either version 2 of the License,  #
#  or (at your option) any later version.                             #
#######################################################################

use strict;

use File::Copy;
use Geo::IP::PurePerl;
use DBI;
use LWP::Simple;
use Archive::Extract;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

#### begin user config ####

# Path to the ban2sql installation
my $install_dir = '/etc/fail2ban/Ban2SQL';

# MySQL variables
my $host = 'localhost';         # hostname of MySQL server.
my $user = 'ban2sql';           # username of the bans database.
my $pw = 'ban2sql';             # password for the bans user.
my $db = 'ban2sql';             # database contains bans table.
my $table = 'bans';             # table containing bans.

# Path to the GeoLiteCity.dat database from MaxMind.
#  Please don't abuse this URL. This is a free version of the database, with limited bandwidth.
my $geodb_url = 'http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz';

# Filename to use when extracting. (should be obvious from the url)
my $tmpdb = $install_dir . '/GeoLiteCity.dat.gz';

# Filename to use when extracted. (if you are using geolite city, keep this value as is)
my $geodb = $install_dir . '/GeoLiteCity.dat';

#### end user config ####

# Display the last 50 bans in the database.
sub ListBans
{
    # Connect to MySQL database.
    my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
      or die "Can't connect to database: $DBI::errstr \n";

    # Prints results.
    print "Bans Collected: \n";

    # Build a query to pull the last 50 bans.
    my $query = "SELECT * FROM `$table` ORDER BY count DESC LIMIT 50";
    # my $query = "SELECT * FROM `fail2ban-perl` ORDER BY count DESC LIMIT 50";
    my $sth = $dbh->prepare( $query ) or die "Failed to Prepare $query \n" . $dbh->errstr;
    $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;

    while ( my @row = $sth->fetchrow_array() )
    {
      print "$row[1]($row[3]): $row[4] | Count: $row[5] | Geo: $row[9] | Last Seen: $row[10] | First Seen: $row[11] \n";
    }
    warn "Error: ", $sth->errstr( ), "\n" if $sth->err();

    # Disconnect from the database now that we are done.
    $sth->finish;
    $dbh->disconnect;

}

# Insert a new ban into the MySQL database.
sub InsertBan
{
                                # Values from Fail2Ban
    my $ban_name = $ARGV[1];    # <name>
    my $ban_protocol = $ARGV[2];# <protocol>
    my $ban_port = $ARGV[3];    # <port>
    my $ban_ip = $ARGV[4];      # <ip>

    # connect to MySQL database
    my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
      or die "Can't connect to database: $DBI::errstr\n";

    # This query will first check to see if the IP is already in the database.
    my ( $ban_count ) = $dbh->selectrow_array( "SELECT count FROM `$table` WHERE ip = '$ban_ip'" );

    # If ban_count is defined then the IP does already exist.
    if ( defined $ban_count )
    {
      # if the record already exists, simply update the counter, and last seen time.
      my $query = "UPDATE `$table` SET count=count+1, date_last_seen=NOW() WHERE ip = '$ban_ip'";
      my $sth = $dbh->prepare( $query ) or die "Failed to Prepare $query \n" . $dbh->errstr;
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
      # Cleanup.
      $sth->finish;
    }
    else # This is a new occurrance.
    {
      # Open GeoIP lookup database.
      my $gi = Geo::IP::PurePerl->open( $geodb, GEOIP_STANDARD )
        or die "Failed to open GeoIP database, check $geodb";

      # Assign the geo location data into the following variables for ban_ip
      my (
          $country_code,
          $country_code3,
          $country_name,
          $region,
          $city,
          $postal_code,
          $latitude,
          $longitude,
          $metro_code,
          $area_code
          ) = $gi->get_city_record( $ban_ip );

      # Grab the port number from the service name passed by fail2ban.
      # This appears to be where the BUG is introduced. When a port range is passed instead of a single port, we get a Fail2Ban error.
      my (
          $service_name,
          $service_alias,
          $service_port,
          $service_protocol ) = getservbyname( $ban_name, $ban_protocol ); 

      # Build the query to insert the ban into the database.
      my $query = "INSERT INTO `$table` values ('', '$service_name', '$service_protocol', '$service_port', '$ban_ip', '1', '$longitude', '$latitude','$country_code', '$city, $region  - $country_name', NOW(), NOW())";

      # Prepare the query we just built.
      my $sth = $dbh->prepare( $query ) or die "Failed to Prepare $query \n" . $dbh->errstr;
      # Execute the query
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
      # Cleanup.
      $sth->finish;
    }

    # Disconnect from the database now that we are done.
    $dbh->disconnect;
}

# Remove an IP from the database.
sub RemoveBan
{
    # The argument passed should be the IP to be removed.
    my $ip_to_remove = $ARGV[1];

    # If nothing is passed with the argument flag.
    unless( $ip_to_remove )
    {
      print "Proper usage: ./ban2sql.pl -d <IP> \n\n",
            " Example: ./ban2sql.pl -d 192.168.100.15 \n\n";
      die;
    }

    # Connect to database.
    my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
      or die "Can't connect to database: $DBI::errstr\n";

    # Find the row for matching ip_to_remove.
    my $query = "SELECT * FROM `$table` WHERE ip='$ip_to_remove'";
    my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
    $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;

    # Display the matching row(s) to be removed.
    while ( my @row = $sth->fetchrow_array() )
    {
      print "$sth->{NAME}->[1]\t$sth->{NAME}->[4]\t\t$sth->{NAME}->[5]\t$sth->{NAME}->[9]\t\t\t$sth->{NAME}->[10]\t\t$sth->{NAME}->[11]\n";
      print "$row[1]\t$row[4]\t$row[5]\t$row[9]\t\t$row[10]\t$row[11] \n";
    }
    warn "Error: ", $sth->errstr( ), "\n" if $sth->err();

    # Prompt the user prior to removing the entry.
    print "Are you sure you would like to remove this entry? [y/n]>  ";
    chomp( my $choice=<STDIN> );
    if ( $choice eq "y" || $choice eq "Y" )
    {
        # If the user agrees, remove the ban.
      $query = "DELETE FROM `$table` WHERE id='$ip_to_remove'";
      my $sth = $dbh->prepare($query) or die "Failed to Prepare $query \n" . $dbh->errstr;
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;
    }

    # Clean-up and disconnect from the database now that we are done.
    $sth->finish;
    $dbh->disconnect;
}

# Clear the database completely of all bans.
sub ClearDatabase
{
    # Prompt the user prior to removing the entries.
    print "This will completely wipe the database of all bans!\nAre you Sure? [y/n]>  ";
    chomp( my $choice=<STDIN> );

    if ( $choice eq "y" || $choice eq "Y" )
    {
      # Connect to MySQL database
      my $dbh = DBI->connect( "DBI:mysql:database=$db:host=$host", $user, $pw )
        or die "Can't connect to database: $DBI::errstr\n";

      # Prepare and execute the removal query.
      my $query = "TRUNCATE TABLE `$table`";
      my $sth = $dbh->prepare( $query ) or die "Failed to Prepare $query \n" . $dbh->errstr;
      $sth->execute or die "Couldn't Execute MySQL Statement: $query \n" . $sth->errstr;

      # Clean-up and disconnect from the database now that we are done.
      $sth->finish;
      $dbh->disconnect;

      print "Database has been wiped!\n";
    }
}

# Update the MaxMind GeoIP database
sub UpdateGeoIP
{
    # First we will ensure if the database exists, back it up first.
    if ( -e $tmpdb )
    {
      # you should really backup the db first in case the download fails.
      my $backup_filename = $tmpdb . '.bak';
      copy( $tmpdb, $backup_filename );
      # Remove the gzip file to save space.
      unlink( $tmpdb );
    }

    # Using the LWP's getstore we will retrieve the file from $geodb_url and rename it to $tmpdb
    getstore ( $geodb_url, $tmpdb ) or die 'Unable to get $geodb_url';

    # Make sure the database actually downloaded, and ungzip it, rename the database to $geodb
    if (-e $tmpdb)
    {
      gunzip $tmpdb => $geodb or die "gunzip failed: $GunzipError\n";
      unlink( $tmpdb ) or die "Failure to Remove file: $tmpdb";
    }
    else
    {
      print "Error Downloading new database. \nTry Again in 24Hours. \n";
    }
}

sub CommandHelp
{
    print "Ban2SQL\n",
        " Usage: ./ban2sql.pl <argument>\n",
        "  -l  : List the last 50 Bans.\n",
        "  -u  : Download the latest MaxMind GeoIP database.\n",
        "  -i  : Insert a new record into the database.\n",
        "  -d  : Remove a record from the database.\n",
        "  -c  : Clear the database and start fresh.\n",
        "  -h  : This help menu.\n\n",
        " This program comes with ABSOLUTELY NO WARRANTY!\n",
        " This is free software, and you are welcome to redistribute it\n",
        " under certain conditions. Please check the README file.\n";
}

# Application's entry point.
if ( @ARGV ge 1 )
{
  if ( $ARGV[0] eq "-i" )
  {
    InsertBan();
  }
  elsif ( $ARGV[0] eq "-l" )
  {
    ListBans();
  }
  elsif ( $ARGV[0] eq "-d" )
  {
    RemoveBan();
  }
  elsif ( $ARGV[0] eq "-c" )
  {
    ClearDatabase();
  }
  elsif ( $ARGV[0] eq "-u" )
  {
    UpdateGeoIP();
  }
  elsif ( $ARGV[0] eq "-h" )
  {
    CommandHelp();
  }
}
else
{
    print "Ban2SQL\nUsage: ./ban2sql.pl -[l|u|i|d|c|h]\n";
}

exit 0;
