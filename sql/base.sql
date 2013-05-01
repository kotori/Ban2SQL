--
-- Table structure for table `ban2sql`
--

DROP TABLE IF EXISTS `ban2sql`;
CREATE TABLE `ban2sql` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` text NOT NULL,
  `protocol` varchar(10) NOT NULL,
  `port` int(11) NOT NULL,
  `ip` varchar(20) NOT NULL,
  `count` int(11) NOT NULL,
  `longitude` varchar(20) DEFAULT NULL,
  `latitude` varchar(20) DEFAULT NULL,
  `country` varchar(5) DEFAULT NULL,
  `geo` varchar(255) DEFAULT NULL,
  `date_last_seen` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `date_first_seen` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=8 DEFAULT CHARSET=latin1;

