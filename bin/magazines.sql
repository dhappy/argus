DROP TABLE IF EXISTS `magazines`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `magazines` (
  `ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ISSNP` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `ISSNE` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Magazine` varchar(300) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Abbr` varchar(900) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Description` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `Publisher` varchar(400) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `JOURNALID` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Site_URL` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `CATEGORY` varchar(445) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `SITEID_OLD` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Previous_Title` varchar(300) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Real_title` varchar(300) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Years` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Volumes` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Prefix` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Timeadded` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`ID`),
  KEY `ISSNP` (`ISSNP`) USING BTREE,
  KEY `ISSNE` (`ISSNE`) USING BTREE,
  KEY `JOURNALID` (`JOURNALID`) USING BTREE,
  KEY `SITEURL` (`Site_URL`),
  KEY `Magazine` (`Magazine`(250))
) ENGINE=MyISAM AUTO_INCREMENT=58537 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `magazines` WRITE;
/*!40000 ALTER TABLE `magazines` DISABLE KEYS */;
/*!40000 ALTER TABLE `magazines` ENABLE KEYS */;
UNLOCK TABLES;
