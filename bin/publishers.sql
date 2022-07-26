DROP TABLE IF EXISTS `publishers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `publishers` (
  `ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `DOICode` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Publisher` varchar(300) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`ID`),
  UNIQUE KEY `doicodeunique` (`DOICode`) USING BTREE
) ENGINE=MyISAM AUTO_INCREMENT=10660 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `publishers` WRITE;
/*!40000 ALTER TABLE `publishers` DISABLE KEYS */;
/*!40000 ALTER TABLE `publishers` ENABLE KEYS */;
UNLOCK TABLES;
