my $statement = qq{
CREATE SCHEMA wiki
  AUTHORIZATION postgres;  

GRANT ALL ON SCHEMA wiki TO postgres;
GRANT ALL ON SCHEMA wiki TO wikidbuser;


-- Table: wiki."Blob_Store"

-- DROP TABLE wiki."Blob_Store";

CREATE TABLE wiki."Blob_Store"
(
  key integer NOT NULL,
  blobkey bytea,
  number_vector numeric,
  value_vector tsvector,
  summary text,
  value text,
  CONSTRAINT blob_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);
ALTER TABLE wiki."Blob_Store"
  OWNER TO wikidbuser;

CREATE INDEX blob_store_value_vector_index
  ON wiki."Blob_Store"
  USING gist
  (value_vector );

CREATE UNIQUE INDEX blob_store_number_vector_index
  ON wiki."Blob_Store"
  USING btree
  (number_vector );

-- Table: wiki."Dataform_Data_Field"

-- DROP TABLE wiki."Dataform_Data_Field";

CREATE TABLE wiki."Dataform_Data_Field"
(
  topic_history_key uuid NOT NULL,
  definition_field_key uuid NOT NULL,
  field_value integer NOT NULL,
  CONSTRAINT dataform_data_key PRIMARY KEY (topic_history_key , definition_field_key )
)
WITH (
  OIDS=FALSE
);

-- Table: wiki."Dataform_Definition_Field"

-- DROP TABLE wiki."Dataform_Definition_Field";

CREATE TABLE wiki."Dataform_Definition_Field"
(
  topic_history_key uuid NOT NULL,
  field_name integer NOT NULL,
  field_type character varying NOT NULL,
  other_info integer NOT NULL,
  CONSTRAINT dataform_definition_key PRIMARY KEY (topic_history_key , field_name )
)
WITH (
  OIDS=FALSE
);



-- Table: wiki."File_Store"

-- DROP TABLE wiki."File_Store";

CREATE TABLE wiki."File_Store"
(
  key character varying NOT NULL,
  file_blob oid,
  blob_store_key integer,
  size integer NOT NULL,
  CONSTRAINT file_store_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);
ALTER TABLE wiki."File_Store"
  OWNER TO wikidbuser;

-- Table: wiki."Group_User_Membership"

-- DROP TABLE wiki."Group_User_Membership";

CREATE TABLE wiki."Group_User_Membership"
(
  user_key uuid NOT NULL,
  group_key uuid NOT NULL,
  topic_history_key uuid NOT NULL,
  CONSTRAINT group_user_key PRIMARY KEY (user_key , group_key , topic_history_key )
)
WITH (
  OIDS=FALSE
);

CREATE INDEX group_user_user_index
  ON wiki."Group_User_Membership"
  USING btree
  ( user_key );

CREATE INDEX group_user_group_index
  ON wiki."Group_User_Membership"
  USING btree
  ( group_key );
  
CREATE INDEX group_user_topic_index
  ON wiki."Group_User_Membership"
  USING btree
  ( topic_history_key );


-- Table: wiki."Groups"

-- DROP TABLE wiki."Groups";

CREATE TABLE wiki."Groups"
(
  key uuid NOT NULL,
  site_key uuid NOT NULL,
  login_name character varying NOT NULL,
  CONSTRAINT group_key PRIMARY KEY (key ),
  CONSTRAINT group_login_name_uniqueness UNIQUE (login_name , site_key )
)
WITH (
  OIDS=FALSE
);

CREATE INDEX group_index
  ON wiki."Groups"
  USING btree
  ( key );


-- Table: wiki."Links"

-- DROP TABLE wiki."Links";

CREATE TABLE wiki."Links"
(
  topic_history_key uuid NOT NULL,
  destination_topic uuid,
  destination_topic_history uuid,
  link_type text NOT NULL,
  blob_key integer,
  original_text text,
  CONSTRAINT links_key_unique_only UNIQUE (topic_history_key , destination_topic , destination_topic_history , link_type , blob_key ),
  CONSTRAINT destination_not_null_check CHECK ('destination_topic'::text <> '00000000-0000-0000-0000-000000000000'::text OR 'destination_topic_history'::text <> '00000000-0000-0000-0000-000000000000'::text OR 'destination_attachment'::text <> '00000000-0000-0000-0000-000000000000'::text OR 'destination_attachment_history'::text <> '00000000-0000-0000-0000-000000000000'::text)
)
WITH (
  OIDS=FALSE
);

CREATE INDEX links_topic_history_index
  ON wiki."Links"
  USING btree
  ( topic_history_key, link_type );

CREATE INDEX links_destination_topic_index
  ON wiki."Links"
  USING btree
  ( destination_topic );

CREATE INDEX links_destination_topic_history_index
  ON wiki."Links"
  USING btree
  ( destination_topic_history );

-- Table: wiki."MetaPreferences_DataTypes"

-- DROP TABLE wiki."MetaPreferences_DataTypes";

CREATE TABLE wiki."MetaPreferences_DataTypes"
(
  name text NOT NULL,
  type text NOT NULL DEFAULT 'Set'::text,
  "from" text,
  "to" text
)
WITH (
  OIDS=FALSE
);
ALTER TABLE wiki."MetaPreferences_DataTypes"
  OWNER TO wikidbuser;

-- Table: wiki."MetaPreferences_History"

-- DROP TABLE wiki."MetaPreferences_History";

CREATE TABLE wiki."MetaPreferences_History"
(
  topic_history_key uuid NOT NULL,
  type text,
  name text NOT NULL,
  value text,
  CONSTRAINT metapreferences_history_key PRIMARY KEY (topic_history_key , type , name )
)
WITH (
  OIDS=FALSE
);



CREATE INDEX metapreferences_history_topic_history_index
  ON wiki."MetaPreferences_History"
  USING btree
  ( topic_history_key,type,name );



-- Table: wiki."Site_History"

-- DROP TABLE wiki."Site_History";

CREATE TABLE wiki."Site_History"
(
  key uuid NOT NULL,
  site_key uuid NOT NULL,
  start_time bigint NOT NULL,
  owner_key character varying NOT NULL,
  owner_group character varying NOT NULL,
  permissions integer NOT NULL,
  CONSTRAINT site_history_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);

-- Table: wiki."Sites"

-- DROP TABLE wiki."Sites";

CREATE TABLE wiki."Sites"
(
  key uuid NOT NULL,
  link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
  site_name text DEFAULT 'Need a real site name'::text,
  local_preferences uuid NOT NULL,
  default_preferences uuid NOT NULL,
  site_home uuid NOT NULL,
  admin_user uuid NOT NULL,
  admin_group uuid NOT NULL,
  system_web uuid NOT NULL,
  trash_web uuid NOT NULL,
  home_web uuid NOT NULL,
  guest_user uuid NOT NULL,
  public_parameters text NOT NULL,
  CONSTRAINT sites_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);

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

-- Index: wiki.thkey_index

-- DROP INDEX wiki.thkey_index;

CREATE UNIQUE INDEX thkey_index
  ON wiki."Topic_History"
  USING btree
  (key );

-- Index: wiki.thtime_index

-- DROP INDEX wiki.thtime_index;

CREATE INDEX thtime_index
  ON wiki."Topic_History"
  USING btree
  (timestamp_epoch );

-- Index: wiki.thtopickey_index

-- DROP INDEX wiki.thtopickey_index;

CREATE INDEX thtopickey_index
  ON wiki."Topic_History"
  USING btree
  (topic_key );

-- Index: wiki.thuser_index

-- DROP INDEX wiki.thuser_index;

CREATE INDEX thuser_index
  ON wiki."Topic_History"
  USING btree
  (user_key );

-- Index: wiki.thweb_index

-- DROP INDEX wiki.thweb_index;

CREATE INDEX thweb_index
  ON wiki."Topic_History"
  USING btree
  (web_key );



-- Table: wiki."Topics"

-- DROP TABLE wiki."Topics";

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

CREATE INDEX topic_link_to_latest
  ON wiki."Topics"
  USING btree
  (link_to_latest );


CREATE UNIQUE INDEX topic_web_topic_index
  ON wiki."Topics"
  USING btree
  (current_web_key , current_topic_name );



-- Table: wiki."User_History"

-- DROP TABLE wiki."User_History";

CREATE TABLE wiki."User_History"
(
  key uuid NOT NULL,
  first_name text,
  last_name text,
  "cUID" text,
  password character varying DEFAULT (-1),
  email text,
  pin_number integer,
  country text DEFAULT 'Japan'::text,
  callback_number character varying,
  gpg_key character varying,
  email_password character varying,
  CONSTRAINT user_history_key PRIMARY KEY (key ),
  CONSTRAINT pin_number_range CHECK (0 < pin_number AND pin_number < 99999999)
)
WITH (
  OIDS=FALSE
);

CREATE INDEX user_history_key_index
  ON wiki."User_History"
  USING btree
  ( key );


-- Table: wiki."Users"

-- DROP TABLE wiki."Users";

CREATE TABLE wiki."Users"
(
  key uuid NOT NULL,
  login_name character varying NOT NULL,
  site_key uuid NOT NULL,
  CONSTRAINT user_key PRIMARY KEY (key ),
  CONSTRAINT user_login_name_uniqueness UNIQUE (login_name , site_key )
)
WITH (
  OIDS=FALSE
);

CREATE INDEX user_login_name_site_index
  ON wiki."Users"
  USING btree
  ( site_key,login_name );

CREATE INDEX user_key_index
  ON wiki."Users"
  USING btree
  ( key );


-- Table: wiki."Web_History"

-- DROP TABLE wiki."Web_History";

CREATE TABLE wiki."Web_History"
(
  key uuid NOT NULL,
  web_key uuid NOT NULL,
  start_time integer NOT NULL,
  site_history_key uuid NOT NULL,
  owner_group character varying NOT NULL,
  permissions integer NOT NULL,
  CONSTRAINT web_history_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);

CREATE INDEX web_history_key_index
  ON wiki."Web_History"
  USING btree
  ( key );
  
-- Table: wiki."Webs"

-- DROP TABLE wiki."Webs";

CREATE TABLE wiki."Webs"
(
  key uuid NOT NULL,
  link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
  web_name text DEFAULT 'Name me something nice'::text,
  site_key uuid NOT NULL,
  web_preferences uuid NOT NULL,
  web_home uuid NOT NULL,
  CONSTRAINT web_key PRIMARY KEY (key )
)
WITH (
  OIDS=FALSE
);

CREATE UNIQUE INDEX webkey_index
  ON wiki."Webs"
  USING btree
  (key );


CREATE INDEX webname_index
  ON wiki."Webs"
  USING btree
  (web_name );



-- Table: wiki.email

-- DROP TABLE wiki.email;

CREATE TABLE wiki.email
(
  message_id character varying NOT NULL,
  user_agent character varying,
  mime_version character varying,
  content_type character varying,
  content_transfer_encoding character varying,
  receiveds text,
  email_references text,
  in_reply_to text
)
WITH (
  OIDS=FALSE
);
ALTER TABLE wiki.email
  OWNER TO wikidbuser;


-- Table: wiki.email_topic_history

-- DROP TABLE wiki.email_topic_history;

CREATE TABLE wiki.email_topic_history
(
  message_id character varying NOT NULL,
  topic_history_key uuid NOT NULL,
  site_key uuid
)
WITH (
  OIDS=FALSE
);
ALTER TABLE wiki.email_topic_history
  OWNER TO wikidbuser;

-- Index: wiki.blobkey_index

-- DROP INDEX wiki.blobkey_index;

CREATE UNIQUE INDEX blobkey_index
  ON wiki."Blob_Store"
  USING btree
  (key );

-- Index: wiki.blobnumber_index

-- DROP INDEX wiki.blobnumber_index;

CREATE INDEX blobnumber_index
  ON wiki."Blob_Store"
  USING btree
  (number_vector );

-- Index: wiki.blobvector_index

-- DROP INDEX wiki.blobvector_index;

CREATE INDEX blobvector_index
  ON wiki."Blob_Store"
  USING gin
  (value_vector );

-- Index: wiki.dfdatadef_index

-- DROP INDEX wiki.dfdatadef_index;

CREATE INDEX dfdatadef_index
  ON wiki."Dataform_Data_Field"
  USING btree
  (definition_field_key );


-- Index: wiki.dfdatathkey_index

-- DROP INDEX wiki.dfdatathkey_index;

CREATE INDEX dfdatathkey_index
  ON wiki."Dataform_Data_Field"
  USING btree
  (topic_history_key );

-- Index: wiki.dfdatavalue_index

-- DROP INDEX wiki.dfdatavalue_index;

CREATE INDEX dfdatavalue_index
  ON wiki."Dataform_Data_Field"
  USING btree
  (field_value );

  -- Index: wiki.dfdeffieldname_index

-- DROP INDEX wiki.dfdeffieldname_index;

CREATE INDEX dfdeffieldname_index
  ON wiki."Dataform_Definition_Field"
  USING btree
  (field_name );

-- Index: wiki.dfdefkey_index

-- DROP INDEX wiki.dfdefkey_index;



-- Index: wiki.dfdefthkey_index

-- DROP INDEX wiki.dfdefthkey_index;

CREATE INDEX dfdefthkey_index
  ON wiki."Dataform_Definition_Field"
  USING btree
  ( topic_history_key );


CREATE OR REPLACE FUNCTION wiki.current_topic_updater()
  RETURNS trigger AS
\$BODY\$
BEGIN

UPDATE wiki."Topics" SET (link_to_latest,current_topic_name,current_web_key) = 

						(NEW."key",NEW.topic_name,NEW.web_key)

WHERE "key" = NEW.topic_key;

RETURN NULL;

END;
\$BODY\$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION wiki.current_topic_updater()
  OWNER TO wikidbuser;


CREATE OR REPLACE FUNCTION wiki.current_web_updater()
  RETURNS trigger AS
\$BODY\$
BEGIN

UPDATE wiki."Webs" SET (link_to_latest) = (NEW."key")
        WHERE "key" = NEW.web_key;

RETURN NULL;

END;
\$BODY\$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION wiki.current_web_updater()
  OWNER TO wikidbuser;


CREATE OR REPLACE FUNCTION wiki.current_site_updater()
  RETURNS trigger AS
\$BODY\$
BEGIN

UPDATE wiki."Sites" SET (link_to_latest) = (NEW."key")
        WHERE "key" = NEW.site_key;

RETURN NULL;

END;
\$BODY\$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION wiki.current_site_updater()
  OWNER TO wikidbuser;


-- Triggers go here

CREATE TRIGGER topic_history_insert_updater_trigger
  AFTER INSERT
  ON wiki."Topic_History"
  FOR EACH ROW
  EXECUTE PROCEDURE wiki.current_topic_updater();

CREATE TRIGGER web_history_insert_updater_trigger
  AFTER INSERT
  ON wiki."Web_History"
  FOR EACH ROW
  EXECUTE PROCEDURE wiki.current_web_updater();

CREATE TRIGGER site_history_insert_updater_trigger
  AFTER INSERT
  ON wiki."Site_History"
  FOR EACH ROW
  EXECUTE PROCEDURE wiki.current_site_updater();

-- Constraints

ALTER TABLE wiki."Dataform_Data_Field"
  OWNER TO wikidbuser,
ADD CONSTRAINT topic_history_dataform_data_relation FOREIGN KEY (topic_history_key)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD CONSTRAINT blob_dataform_data_relation FOREIGN KEY (field_value)
      REFERENCES wiki."Blob_Store" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;


ALTER TABLE wiki."Dataform_Definition_Field"
  OWNER TO wikidbuser,

ADD  CONSTRAINT dataform_definition_blob_name_relation FOREIGN KEY (field_name)
      REFERENCES wiki."Blob_Store" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT dataform_definition_blob_other_relation FOREIGN KEY (other_info)
      REFERENCES wiki."Blob_Store" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT dataform_definition_topic_history_relation FOREIGN KEY (topic_history_key)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE wiki."Group_User_Membership"
  OWNER TO wikidbuser,
ADD  CONSTRAINT group_user_groups_relation FOREIGN KEY (group_key)
      REFERENCES wiki."Groups" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT group_user_topic_history_relation FOREIGN KEY (topic_history_key)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT group_user_users_relation FOREIGN KEY (user_key)
      REFERENCES wiki."Users" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."Groups"
  OWNER TO wikidbuser,
ADD CONSTRAINT group_site_relation FOREIGN KEY (site_key)
      REFERENCES wiki."Sites" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD CONSTRAINT group_topic_relation FOREIGN KEY (key)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE wiki."Links"
  OWNER TO wikidbuser,
ADD  CONSTRAINT link_topic_relation FOREIGN KEY (destination_topic)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT link_topic_history_relation FOREIGN KEY (destination_topic_history)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."MetaPreferences_History"
  OWNER TO wikidbuser,
ADD  CONSTRAINT metapreferences_history_topic_history_relation FOREIGN KEY (topic_history_key)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE wiki."Sites"
  OWNER TO wikidbuser,
ADD  CONSTRAINT site_admin_relation FOREIGN KEY (admin_user)
      REFERENCES wiki."Users" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_admingroup_relation FOREIGN KEY (admin_group)
      REFERENCES wiki."Groups" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_default_relation FOREIGN KEY (default_preferences)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_guest_relation FOREIGN KEY (guest_user)
      REFERENCES wiki."Users" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_home_relation FOREIGN KEY (home_web)
      REFERENCES wiki."Webs" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_local_relation FOREIGN KEY (local_preferences)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_system_web_relation FOREIGN KEY (system_web)
      REFERENCES wiki."Webs" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT site_trash_relation FOREIGN KEY (trash_web)
      REFERENCES wiki."Webs" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;


ALTER TABLE wiki."Site_History"
  OWNER TO wikidbuser,
ADD  CONSTRAINT site_history_site_relation FOREIGN KEY (site_key)
      REFERENCES wiki."Sites" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE wiki."Topics"
  OWNER TO wikidbuser,
ADD  CONSTRAINT link_topic_relation FOREIGN KEY (link_to_latest)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT web_topic_relation FOREIGN KEY (current_web_key)
      REFERENCES wiki."Webs" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;


ALTER TABLE wiki."Topic_History"
  OWNER TO wikidbuser,
ADD  CONSTRAINT topic_history_user_relation FOREIGN KEY (user_key)
      REFERENCES wiki."Users" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT user_topic_history_relation FOREIGN KEY (user_key)
      REFERENCES wiki."Users" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT web_topic_history_relation FOREIGN KEY (web_key)
      REFERENCES wiki."Webs" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."Users"
  OWNER TO wikidbuser,
ADD  CONSTRAINT user_site_relation FOREIGN KEY (site_key)
      REFERENCES wiki."Sites" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT user_topic_relation FOREIGN KEY (key)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."User_History"
  OWNER TO wikidbuser,
ADD CONSTRAINT user_history_topic_history_relation FOREIGN KEY (key)
      REFERENCES wiki."Topic_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."Web_History"
  OWNER TO wikidbuser,
ADD CONSTRAINT web_site_relation FOREIGN KEY (site_history_key)
      REFERENCES wiki."Site_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE wiki."Webs"
  OWNER TO wikidbuser,
ADD  CONSTRAINT site_web_relation FOREIGN KEY (site_key)
      REFERENCES wiki."Sites" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT web_home_relation FOREIGN KEY (web_home)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT web_link_to_latest_relation FOREIGN KEY (link_to_latest)
      REFERENCES wiki."Web_History" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE,
ADD  CONSTRAINT web_preferences_relation FOREIGN KEY (web_preferences)
      REFERENCES wiki."Topics" (key) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;

-- Japanese functions
SET search_path = wiki;

--
-- Japanese text parser
--

CREATE FUNCTION ts_ja_start(internal, int4)
    RETURNS internal
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' STRICT;

CREATE FUNCTION ts_ja_gettoken(internal, internal, internal)
    RETURNS internal
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' STRICT;

CREATE FUNCTION ts_ja_end(internal)
    RETURNS void
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' STRICT;

CREATE TEXT SEARCH PARSER pg_catalog.japanese (
    START    = ts_ja_start,
    GETTOKEN = ts_ja_gettoken,
    END      = ts_ja_end,
    HEADLINE = pg_catalog.prsd_headline,
    LEXTYPES = pg_catalog.prsd_lextype
);
COMMENT ON TEXT SEARCH PARSER pg_catalog.japanese IS
    'japanese word parser';

--
-- Japanese text lexizer
--

CREATE FUNCTION ts_ja_lexize(internal, internal, internal, internal)
    RETURNS internal
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' STRICT;

CREATE TEXT SEARCH TEMPLATE pg_catalog.mecab (
	LEXIZE = ts_ja_lexize
);

CREATE TEXT SEARCH DICTIONARY pg_catalog.japanese_stem (
	TEMPLATE = pg_catalog.mecab
);

--
-- Japanese text configuration
--

CREATE TEXT SEARCH CONFIGURATION pg_catalog.japanese (PARSER = japanese);
COMMENT ON TEXT SEARCH CONFIGURATION pg_catalog.japanese IS
    'configuration for japanese language';

ALTER TEXT SEARCH CONFIGURATION pg_catalog.japanese ADD MAPPING
    FOR email, url, url_path, host, file, version,
        sfloat, float, int, uint,
        numword, hword_numpart, numhword
    WITH simple;

-- Default configuration is Japanese-English.
-- Replace english_stem if you use other language.
ALTER TEXT SEARCH CONFIGURATION pg_catalog.japanese ADD MAPPING
    FOR asciiword, hword_asciipart, asciihword
    WITH english_stem;

ALTER TEXT SEARCH CONFIGURATION pg_catalog.japanese ADD MAPPING
    FOR word, hword_part, hword
    WITH japanese_stem;

--
-- Utility functions
--

CREATE FUNCTION ja_analyze(
        text,
        OUT word text,
        OUT type text,
        OUT subtype1 text,
        OUT subtype2 text,
        OUT subtype3 text,
        OUT conjtype text,
        OUT conjugation text,
        OUT basic text,
        OUT ruby text,
        OUT pronounce text)
    RETURNS SETOF record
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

CREATE FUNCTION ja_normalize(text)
    RETURNS text
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

CREATE FUNCTION ja_wakachi(text)
    RETURNS text
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

CREATE FUNCTION web_query(text) RETURNS text AS
\$\$
  SELECT regexp_replace(regexp_replace(regexp_replace(\$1,
    E'(^|\\s+)-', E'\\1!', 'g'),
    E'\\s+OR\\s+', '|', 'g'),
    E'\\s+', '&', 'g');
\$\$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION furigana(text)
    RETURNS text
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

CREATE FUNCTION hiragana(text)
    RETURNS text
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

CREATE FUNCTION katakana(text)
    RETURNS text
    AS '\$libdir/textsearch_ja'
    LANGUAGE 'C' IMMUTABLE STRICT;

--




-- Dictionaries
CREATE TEXT SEARCH DICTIONARY wiki.simple_english (
   TEMPLATE = simple,
   stopwords = 'english'
);
CREATE TEXT SEARCH DICTIONARY wiki.simple_portuguese (
   TEMPLATE = simple,
   stopwords = 'portuguese'
);
CREATE TEXT SEARCH DICTIONARY wiki.simple_spanish (
   TEMPLATE = simple,
   stopwords = 'spanish'
);
CREATE TEXT SEARCH DICTIONARY wiki.snowball_english (
   TEMPLATE = snowball,
   language = 'english'
);



CREATE TEXT SEARCH CONFIGURATION wiki.all_languages (
  PARSER = japanese
);
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR asciihword WITH english_stem;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR asciiword WITH english_stem;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR email WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR file WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR float WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR host WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR hword WITH english_stem;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR hword_asciipart WITH english_stem;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR hword_numpart WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR hword_part WITH english_stem;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR int WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR numhword WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR numword WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR sfloat WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR uint WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR url WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR url_path WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR version WITH simple;
ALTER TEXT SEARCH CONFIGURATION wiki.all_languages ADD MAPPING FOR word WITH japanese_stem,english_stem;

  
};

sub executeInsert {
	require DBI;
	# Setup all off of db_connections
	#  Note: dbconnection_read is for doing SELECT queries only, while dbconnection_write is for doing transactions
	my $DB_name = 'wikidb';
	my $DB_host = 'localhost';
	my $DB_user = 'postgres';
	my $DB_pwd = 'put secret password here';	
	my $dbconnection = DBI->connect("dbi:Pg:dbname=$DB_name;host=$DB_host",$DB_user,$DB_pwd, {'RaiseError' => 1}) or return "DB Death!";
	$dbconnection->{AutoCommit} = 0;  # disable transactions
	
	my $handler = $dbconnection->prepare($statement);
	$handler->execute();
	$dbconnection->commit;
	$dbconnection->disconnect();

}

eval{
	executeInsert();
};
if($@){
	print "Problem!\n$@\n";
}
else{
	print "Success!\n";
}
