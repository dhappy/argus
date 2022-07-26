DROP TABLE IF EXISTS `scimag`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `scimag` (
  `ID` int(15) unsigned NOT NULL AUTO_INCREMENT,
  `DOI` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL,
  `DOI2` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Title` varchar(2000) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Author` varchar(2000) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Year` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Month` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Day` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Volume` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Issue` varchar(95) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `First_page` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Last_page` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Journal` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `ISBN` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `ISSNP` varchar(11) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `ISSNE` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `MD5` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Filesize` int(11) unsigned NOT NULL,
  `TimeAdded` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `JOURNALID` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `AbstractURL` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Attribute1` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Attribute2` varchar(1000) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Attribute3` varchar(2000) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Attribute4` varchar(5000) COLLATE utf8mb4_unicode_ci DEFAULT '',
  `Attribute5` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Attribute6` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `visible` char(3) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `PubmedID` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `PMC` varchar(12) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `PII` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`ID`) USING BTREE,
  UNIQUE KEY `DOIUNIQUE` (`DOI`) USING BTREE,
  KEY `VOLUMEINDEX` (`Volume`) USING BTREE,
  KEY `ISSUEINDEX` (`Issue`) USING BTREE,
  KEY `ISSNPINDEX` (`ISSNP`) USING BTREE,
  KEY `YEARINDEX` (`Year`) USING BTREE,
  KEY `ISSNEINDEX` (`ISSNE`),
  KEY `DOIINDEX` (`DOI`) USING BTREE,
  KEY `JOURNALID` (`JOURNALID`) USING BTREE,
  KEY `DOIINDEX2` (`DOI2`) USING BTREE,
  KEY `PUBMEDINDEX` (`PubmedID`) USING BTREE,
  KEY `MD5` (`MD5`) USING BTREE,
  KEY `VISIBLEID` (`visible`,`ID`) USING BTREE,
  FULLTEXT KEY `FULLTEXT` (`Title`,`Author`)
) ENGINE=MyISAM AUTO_INCREMENT=82083413 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `scimag` WRITE;
/*!40000 ALTER TABLE `scimag` DISABLE KEYS */;
/*!40000 ALTER TABLE `scimag` ENABLE KEYS */;
UNLOCK TABLES;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50017 DEFINER=`root`@`localhost`*/ /*!50003 TRIGGER `scimag_insert_all` BEFORE INSERT ON `scimag`
  FOR EACH ROW
BEGIN

IF (SELECT NEW.`md5` REGEXP '^[0-9A-Fa-f]{32}$')=1 THEN 
  IF (SELECT count(*) FROM `technical`.`md5_all` WHERE `md5` = NEW.`md5`) =0 THEN
    INSERT INTO `technical`.`md5_all` (`MD5`, `scimag`) VALUES (NEW.`md5`, CASE WHEN NEW.`visible`='' THEN 1 ELSE 2 END);
  ELSEIF (SELECT `scimag` FROM `technical`.`md5_all` WHERE `md5` =NEW.`md5`) in (0,3) THEN
    UPDATE `technical`.`md5_all` SET `scimag`=CASE WHEN NEW.`visible`='' THEN 1 ELSE 2 END WHERE `md5` = NEW.`md5`;
  END IF;
  ELSE
  	set @msg1 = concat("DIE: MD5 is inconsisently ", NEW.`md5`);
  	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @msg1;
 END IF;
 
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50017 DEFINER=`root`@`localhost`*/ /*!50003 TRIGGER `scimag_update_all` BEFORE UPDATE ON `scimag`
  FOR EACH ROW
BEGIN


IF (SELECT NEW.`md5` REGEXP '^[0-9A-Fa-f]{32}$')=1 THEN 

  IF NEW.`md5` != OLD.`md5` THEN
    UPDATE `technical`.`md5_all` SET `scimag`=0 WHERE `md5` = OLD.`md5`;
    
   -- DELETE FROM `libgen_scimag`.`scimag_edited` WHERE `MD5`= OLD.`md5`;


    IF (SELECT count(*) FROM `technical`.`md5_all` WHERE `md5` = NEW.`md5`) =0 THEN
      INSERT INTO `technical`.`md5_all` (`MD5`, `scimag`) VALUES (NEW.`md5`, CASE WHEN NEW.`visible` ='' THEN 1 ELSE 2 END);
    ELSEIF (SELECT `scimag` FROM `technical`.`md5_all` WHERE `md5` =NEW.`md5` LIMIT 1) in (0,3) THEN
      UPDATE `technical`.`md5_all` SET `scimag`=CASE WHEN NEW.`visible` ='' THEN 1 ELSE 2 END WHERE `md5` = NEW.`md5`;
    END IF;
  END IF;
  
ELSE   	
	set @msg1 = concat("DIE: MD5 is inconsisently ", NEW.`md5`);
  	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @msg1;  
END IF;

IF NEW.`visible` != OLD.`visible` AND NEW.`visible` = '' THEN
  UPDATE `technical`.`md5_all` SET `scimag`=1 WHERE `md5`=NEW.`md5`;
ELSEIF NEW.`visible` != OLD.`visible` AND NEW.`visible` != '' THEN
  UPDATE `technical`.`md5_all` SET `scimag`=2 WHERE `md5`=NEW.`md5`;
END IF;


SET @batchid = IF(@batchid, @batchid, ROUND(RAND() * 10000000000000000));
SET @timeid =  NOW(); -- IF(@timeid, @timeid, NEW.timelastmodified);
SET NEW.timeadded = @timeid;
IF NEW.Attribute5='manual' THEN

IF NEW.`DOI`!=OLD.`DOI` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'DOI', 'upd', OLD.`DOI`, NEW.`DOI`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`DOI2`!=OLD.`DOI2` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'DOI2', 'upd', OLD.`DOI2`, NEW.`DOI2`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Title`!=OLD.`Title` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Title', 'upd', OLD.`Title`, NEW.`Title`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Author`!=OLD.`Author` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Author', 'upd', OLD.`Author`, NEW.`Author`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Year`!=OLD.`Year` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Year', 'upd', OLD.`Year`, NEW.`Year`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Month`!=OLD.`Month` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Month', 'upd', OLD.`Month`, NEW.`Month`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Day`!=OLD.`Day` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Day', 'upd', OLD.`Day`, NEW.`Day`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Volume`!=OLD.`Volume` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Volume', 'upd', OLD.`Volume`, NEW.`Volume`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Issue`!=OLD.`Issue` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Issue', 'upd', OLD.`Issue`, NEW.`Issue`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`First_page`!=OLD.`First_page` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'First_page', 'upd', OLD.`First_page`, NEW.`First_page`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Last_page`!=OLD.`Last_page` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Last_page', 'upd', OLD.`Last_page`, NEW.`Last_page`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Journal`!=OLD.`Journal` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Journal', 'upd', OLD.`Journal`, NEW.`Journal`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`ISBN`!=OLD.`ISBN` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'ISBN', 'upd', OLD.`ISBN`, NEW.`ISBN`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`ISSNP`!=OLD.`ISSNP` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'ISSNP', 'upd', OLD.`ISSNP`, NEW.`ISSNP`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`ISSNE`!=OLD.`ISSNE` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'ISSNE', 'upd', OLD.`ISSNE`, NEW.`ISSNE`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`Filesize`!=OLD.`Filesize` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Filesize', 'upd', OLD.`Filesize`, NEW.`Filesize`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`JOURNALID`!=OLD.`JOURNALID` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'JOURNALID', 'upd', OLD.`JOURNALID`, NEW.`JOURNALID`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`AbstractURL`!=OLD.`AbstractURL` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'AbstractURL', 'upd', OLD.`AbstractURL`, NEW.`AbstractURL`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
 IF NEW.`Attribute1`!=OLD.`Attribute1` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute1', 'upd', OLD.`Attribute1`, NEW.`Attribute1`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
 IF NEW.`Attribute2`!=OLD.`Attribute2` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute2', 'upd', OLD.`Attribute2`, NEW.`Attribute2`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
 IF NEW.`Attribute3`!=OLD.`Attribute3` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute3', 'upd', OLD.`Attribute3`, NEW.`Attribute3`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
 IF NEW.`Attribute4`!=OLD.`Attribute4` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute4', 'upd', OLD.`Attribute4`, NEW.`Attribute4`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
-- IF NEW.`Attribute5`!=OLD.`Attribute5` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute5', 'upd', OLD.`Attribute5`, NEW.`Attribute5`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
 IF NEW.`Attribute6`!=OLD.`Attribute6` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'Attribute6', 'upd', OLD.`Attribute6`, NEW.`Attribute6`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`visible`!=OLD.`visible` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'visible', 'upd', OLD.`visible`, NEW.`visible`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`PubmedID`!=OLD.`PubmedID` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'PubmedID', 'upd', OLD.`PubmedID`, NEW.`PubmedID`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`PMC`!=OLD.`PMC` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'PMC', 'upd', OLD.`PMC`, NEW.`PMC`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;
IF NEW.`PII`!=OLD.`PII` THEN INSERT INTO `technical`.`change_history` (`lg_topic`, `table`, `field`, `action`, `old_value`, `new_value`, `time_modified`, `table_id`, `batch_id`,`md5`) VALUES ('scimag', 'scimag', 'PII', 'upd', OLD.`PII`, NEW.`PII`, @timeid, NEW.id, @batchid, NEW.`md5`); END IF;

END IF;

IF NEW.`md5`!=OLD.`md5` THEN 
VALUES                                    ('scimag',  'scimag',       'md5',   'del',     OLD.md5,     NEW.md5,     @timeid,         NEW.id,     @batchid,  NEW.`md5`);
END IF;


END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50017 DEFINER=`root`@`localhost`*/ /*!50003 TRIGGER `scimag_delete_all` BEFORE DELETE ON `scimag`
  FOR EACH ROW
BEGIN

    UPDATE `technical`.`md5_all` SET `scimag`=0 WHERE `md5` = OLD.`md5`;
   -- DELETE FROM `libgen_scimag`.`scimag_edited` WHERE `md5`=OLD.`md5`;
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
