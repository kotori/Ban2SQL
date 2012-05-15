Ban2SQL 
=======

* * *
------------
Requirements
------------

There are a couple of requirements prior to running Ban2SQL. First is Fail2Ban, while its not an 
absolute requirement, it does automate the insertion of bans into the database. Ban2SQL was written 
in Perl, so there are a few modules you will need to install. File::Copy, Geo::IP::PurePerl, DBI,
LWP::Simple, Archive::Extract, IO::Uncompress::Gunzip.

* * *                          
------------
Installation
------------

1. Create a MySQL database called ban2sql (this step isn't necessary if you are sharing a db)
<code>
   $ mysql -u'root' -p
   $ mysql> CREATE DATABASE `ban2sql`;
</code>

2. Create ban2sql MySQL user to access ban2sql database (needs INSERT, UPDATE, DELETE)
<pre><code>
   $ mysql -u'root' -p
   $ mysql> CREATE USER 'ban2sql_user'@'localhost' IDENTIFIED BY 'ban2sql_password';
   $ mysql> GRANT INSERT, UPDATE, DELETE, SELECT PRIVILEGES ON `ban2sql`.* to 'ban2sql_user'@'localhost';
</code></pre>

3. Create table by piping base.sql into mysql (mysql -u'ban2sql_user' -p'ban2sql_password' `ban2sql` < sql/base.sql)
<pre><code>
   $ mysql -u'ban2sql_user' -p'ban2sql_password' `ban2sql` &lt; sql/base.sql
</code></pre>
   You can also populate your table with some sample data by piping data.sql into your new table.
<pre><code>
   $ mysql -u'ban2sql_user' -p'ban2sql_password' `ban2sql` &lt; sql/data.sql
</code></pre>

4. Edit ban2sql.pl and change home path and sql login details at the top of the file.

5. Update Geo IP Database (./ban2sql.pl -u)

6. Tell fail2ban to call ban2sql by appending to actionban in your action script.
   Usually the default action is 'banaction = iptables-multiport'

Example for /etc/fail2ban/action.d/iptables-multiport.conf
<pre><code>
actionban = iptables -I fail2ban-&lt;name&gt; 1 -s &lt;ip&gt; -j DROP
            /etc/fail2ban/ban2sql/ban2sql.pl &lt;name&gt; &lt;protocol&gt; &lt;port&gt; &lt;ip&gt;
</code></pre>

* * *
-----
Usage
-----
<pre><code>
 Usage: ./ban2sql.pl &lt;argument&gt;
  -l  : List the last 50 Bans.
  -u  : Download the latest MaxMind GeoIP database.
  -i  : Insert a new record into the database.
  -d  : Remove a record from the database.
  -c  : Clear the database and start fresh.
  -h  : The help menu.
</code></pre>

* * *
-----
Notes
-----

Incase its not immediately obvious, here is a breakdown of how the database is built.
This might be handy incase you would like to tweak the application (add db rows, etc).

MySQL Database Row Chart
<table>
  <tr>
    <th>Row ID</th><th>Row Name</th><th>Row Meaning</th>
  </tr>
  <tr>
    <td>1</td><td>name</td><td>Service being attacked (ssh, ftp, etc..)</td>
  </tr>
  <tr>
    <td>2</td><td>protocol</td><td>Protocol this attack is taking place over</td>
  </tr>
  <tr>
    <td>3</td><td>port</td><td>Port number this service attack is taking place on</td>
  </tr>
  <tr>
    <td>4</td><td>ip</td><td>IP address of the attacker</td>
  </tr>
  <tr>
    <td>5</td><td>count</td><td>Number of attempts this ip has made</td>
  </tr>
  <tr>
    <td>6</td><td>longitude</td><td>Geolocational longitude of attacker</td>
  </tr>
  <tr>
    <td>7</td><td>latitude</td><td>Geolocational latitude of attacker</td>
  </tr>
  <tr>
    <td>8</td><td>country</td><td>Country this attacker originates from (2 letters)</td>
  </tr>
  <tr>
    <td>9</td><td>geo</td><td>More specific regional information about this attacker</td>
  </tr>
  <tr>
    <td>10</td><td>date_last_seen</td><td>Date/Time of latest ban</td>
  </tr>
  <tr>
    <td>11</td><td>date_first_seen</td><td>Date/Time of first ban</td>
  </tr>
</table>

* * *
---------------
Contact/Credits
---------------
Ban2SQL v2.0 by Kotori <kotori@greenskin.hopto.org>
<br>
Based off of Fail2SQL v1.0 by Jordan Tomkinson <jordan@moodle.com>
<br>
Project Page: https://github.com/kotori/Ban2SQL
