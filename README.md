# Background
I began to work on a fork of foswiki so that I would be able to use a relational database as the backend sometime in 2011.  I completed the project sometime around 2012 and have been using this setup for the last 3 to 4 years.  The primary goal was to figure out a way to separate the content from data structure as much as possible in order to encrypt the wiki.  At the time, there was a lot of buzz around NoSQL paradigms.  However, with those paradigms, the structure of the data is mixed in with the content, making it very difficult to come up with a solution to encrypt the wiki.

# Summary
I forked Foswiki version 1.1.?.

Most of the relational database fork related code is located in [DBIStoreContrib](https://github.com/favioflamingo/wiki/tree/master/perl/lib/Foswiki/Contrib/DBIStoreContrib).  However, some irreversible changes were made to the main core.  The changes to the core code have to do with the difficulty of uniquely identifying changes to the data over time.  So, first, before going over where to find the interesting code, I will go over the data structure.

The fork runs with Japanese text with no problems.

# Data
To see the SQL statements, just grep the DBIStoreContrib directory for this string, _$selectStatement_ .  To see a schema, check out [schema.pl](https://github.com/favioflamingo/wiki/blob/master/static/var/lib/foswiki/data/schema.pl).


To start with, take a look at [the Meta Topic object](https://github.com/favioflamingo/wiki/blob/master/perl/lib/Foswiki/Meta.pm).  To create a brand new object, the user enters the following information:

1. WebName - must correspond to an existing Web
1. TopicName - the combination of (WebName,TopicName) must be unique at the time when _$metatopic->save_ is run
1. content 
1. other stuff - FormData, etc.. talked about later in the plugin section

While the user sees the above information, what the user does not see or ever need to know is that when a brand new topic is created, a random UUID (a 32 byte number) has to be created to represent the new topic.  Further more, while a (WebName,TopicName) may uniquely identify a single topic at a single point in time, that pair is not capable of identifying a topic uniquely over time.  And when normalizing a data set and separating structure, it is necessary to be able to identify all topics uniquely across time.  So, in that case, we could just use (WebName,TopicName, timestamp) to identify a topic.  However, it is much easier to just create random UUID and use that to identify a topic.  Therefore the following two SQL tables were created:

* Topics:
```sql
CREATE TABLE wiki."Topics"
(
key uuid NOT NULL,
link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
current_web_key uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
current_topic_name integer NOT NULL,
CONSTRAINT topic_key PRIMARY KEY (key )
)
WITH (
OIDS=FALSE
);
```

* Topic_History:
```sql
-- Table: wiki."Topic_History"
-- DROP TABLE wiki."Topic_History";
CREATE TABLE wiki."Topic_History"
(
key uuid NOT NULL,
topic_key uuid NOT NULL,
topic_name integer NOT NULL,
revision integer DEFAULT (-1),
user_key uuid NOT NULL,
web_key uuid NOT NULL,
timestamp_epoch integer NOT NULL,
owner uuid NOT NULL,
"group" uuid NOT NULL,
permissions integer NOT NULL,
topic_content integer NOT NULL,
CONSTRAINT topic_history_key PRIMARY KEY (key )
)
WITH (
OIDS=FALSE
);
```
