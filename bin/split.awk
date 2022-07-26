#!/usr/bin/env awk

# https://blog.twineworks.com/converting-a-mysql-dump-to-csv-files-b5e92d7cc5dd

BEGIN {
  # file starts with DDL statements that go into header.sql

  table = "header";
  sql = 1
}

{
  # -- step 1 --
  # determine whether current line contains a DDL sql statement or
  # table data

  if ($0 ~ "^INSERT INTO "){
    # this is a data line for the current table, it goes into a csv file
    sql = 0
  }
  else if ($0 ~ "^DROP TABLE IF EXISTS"){
    # a new table is coming up
    # remember the name
    # output goes to sql file
    table = gensub(/DROP TABLE IF EXISTS `(.+)`;/, "\\1", "g" $0);
    sql = 1
  }
  else {
    # any other lines belong to the sql file of the current table
    sql = 1
  }

  # -- step 2 --
  # transform and write the line into target file

  if (sql == 1){
    # sql lines are appended to the <table_name>.sql file
    print > table".sql";
  }
  else {

    # data lines are split and written as individual csv records

    # inserts are of the form:
    # INSERT INTO `borders` VALUES ('A','D',784),...,('ZW','Z',797);

    # splitting on three separators:
    #   INSERT INTO `table_name` VALUES (   -- beginning of line
    #   ),(                                 -- record separator
    #   );                                  -- end of line

    # split records are collected in array 'a'

    n = split($0, a, /(^INSERT INTO `[^`]*` VALUES \()|(\),\()|(\);$)/)

    for(i=1;i<=n;i++) {
      # first and last splits may be empty strings
      len = length(a[i])
      if (len > 0) {
        # if record is not empty, output to <table_name>.csv file
        data = a[i]
        print data > table".csv";
      }
    }
  }
}

END {}