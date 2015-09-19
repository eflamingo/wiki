--
-- PostgreSQL database dump
--

-- Dumped from database version 9.1.12
-- Dumped by pg_dump version 9.4.3
-- Started on 2015-09-19 16:59:11 JST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = foswiki, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 189 (class 1259 OID 24923)
-- Name: Attachment_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Attachment_History" (
    key uuid NOT NULL,
    topic_key uuid NOT NULL,
    version integer DEFAULT nextval('attachment_history_revision'::regclass),
    path text,
    size integer,
    timestamp_epoch integer NOT NULL,
    user_key uuid NOT NULL,
    attr text,
    file_name text NOT NULL,
    file_type text NOT NULL,
    blob_store_key bytea,
    file_store_key text NOT NULL,
    attachment_key uuid NOT NULL,
    comment bytea
);


ALTER TABLE "Attachment_History" OWNER TO postgres;

--
-- TOC entry 190 (class 1259 OID 24930)
-- Name: Attachments; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Attachments" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_attachment_name text DEFAULT 'Some Unknown File Name'::text,
    current_topic_key uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid
);


ALTER TABLE "Attachments" OWNER TO postgres;

--
-- TOC entry 191 (class 1259 OID 24939)
-- Name: Blob_Store; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Blob_Store" (
    value text NOT NULL,
    key bytea NOT NULL,
    summary text,
    value_vector pg_catalog.tsvector,
    number_vector numeric
);


ALTER TABLE "Blob_Store" OWNER TO postgres;

--
-- TOC entry 199 (class 1259 OID 25013)
-- Name: Topics; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Topics" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_web_key uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_topic_name bytea NOT NULL
);


ALTER TABLE "Topics" OWNER TO postgres;

--
-- TOC entry 202 (class 1259 OID 25028)
-- Name: Topic_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Topic_History" (
    key uuid NOT NULL,
    topic_key uuid NOT NULL,
    user_key uuid NOT NULL,
    revision integer DEFAULT nextval('topic_history_revision'::regclass),
    web_key uuid NOT NULL,
    timestamp_epoch integer NOT NULL,
    topic_content bytea NOT NULL,
    topic_name bytea NOT NULL,
    fake_topic_history_key uuid
);


ALTER TABLE "Topic_History" OWNER TO postgres;

--
-- TOC entry 204 (class 1259 OID 25039)
-- Name: Dataform_Data_Field; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Dataform_Data_Field" (
    field_key uuid NOT NULL,
    definition_field_key uuid NOT NULL,
    field_value bytea NOT NULL,
    topic_history_key uuid NOT NULL
);


ALTER TABLE "Dataform_Data_Field" OWNER TO postgres;

--
-- TOC entry 205 (class 1259 OID 25045)
-- Name: Dataform_Data_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Dataform_Data_History" (
    key uuid NOT NULL,
    topic_history_key uuid NOT NULL,
    definition_key uuid NOT NULL,
    "values" bytea NOT NULL
);


ALTER TABLE "Dataform_Data_History" OWNER TO postgres;

--
-- TOC entry 206 (class 1259 OID 25051)
-- Name: Dataform_Definition_Field; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Dataform_Definition_Field" (
    field_key uuid NOT NULL,
    topic_history_key uuid NOT NULL,
    field_name bytea NOT NULL,
    field_type character varying NOT NULL,
    other_info bytea NOT NULL
);


ALTER TABLE "Dataform_Definition_Field" OWNER TO postgres;

--
-- TOC entry 207 (class 1259 OID 25057)
-- Name: Dataform_Definition_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Dataform_Definition_History" (
    key uuid NOT NULL,
    value bytea NOT NULL
);


ALTER TABLE "Dataform_Definition_History" OWNER TO postgres;

--
-- TOC entry 208 (class 1259 OID 25063)
-- Name: EditTable_Data; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "EditTable_Data" (
    key uuid NOT NULL,
    row_blob bytea,
    topic_history_key uuid NOT NULL,
    row_number integer NOT NULL,
    definition_key bytea NOT NULL
);


ALTER TABLE "EditTable_Data" OWNER TO postgres;

--
-- TOC entry 209 (class 1259 OID 25069)
-- Name: Example_Topics; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Example_Topics" (
    topic_name text NOT NULL,
    web_name text NOT NULL,
    topic_content text NOT NULL
);


ALTER TABLE "Example_Topics" OWNER TO postgres;

--
-- TOC entry 210 (class 1259 OID 25075)
-- Name: File_Store; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "File_Store" (
    key character varying NOT NULL,
    file_blob oid,
    blob_store_key bytea,
    size integer NOT NULL
);


ALTER TABLE "File_Store" OWNER TO postgres;

--
-- TOC entry 211 (class 1259 OID 25081)
-- Name: Group_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Group_History" (
    key uuid NOT NULL,
    group_name text,
    group_key uuid NOT NULL,
    email text,
    timestamp_epoch integer NOT NULL,
    user_key uuid NOT NULL
);


ALTER TABLE "Group_History" OWNER TO postgres;

--
-- TOC entry 212 (class 1259 OID 25087)
-- Name: Group_User_Membership; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Group_User_Membership" (
    user_key uuid NOT NULL,
    group_key uuid NOT NULL,
    topic_history_key uuid NOT NULL
);


ALTER TABLE "Group_User_Membership" OWNER TO postgres;

--
-- TOC entry 213 (class 1259 OID 25090)
-- Name: Groups; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Groups" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    group_topic_key uuid NOT NULL,
    site_key uuid NOT NULL
);


ALTER TABLE "Groups" OWNER TO postgres;

--
-- TOC entry 214 (class 1259 OID 25094)
-- Name: Link_Types; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Link_Types" (
    link_type_key text NOT NULL
);


ALTER TABLE "Link_Types" OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 25100)
-- Name: Links; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Links" (
    key uuid NOT NULL,
    topic_history_key uuid NOT NULL,
    destination_topic uuid,
    destination_attachment uuid,
    link_type text NOT NULL,
    destination_topic_history uuid,
    destination_attachment_history uuid,
    blob_key bytea,
    original_text text,
    CONSTRAINT destination_not_null_check CHECK ((((('destination_topic'::text <> '00000000-0000-0000-0000-000000000000'::text) OR ('destination_topic_history'::text <> '00000000-0000-0000-0000-000000000000'::text)) OR ('destination_attachment'::text <> '00000000-0000-0000-0000-000000000000'::text)) OR ('destination_attachment_history'::text <> '00000000-0000-0000-0000-000000000000'::text)))
);


ALTER TABLE "Links" OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 25107)
-- Name: MetaPreferences_DataTypes; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "MetaPreferences_DataTypes" (
    type text DEFAULT 'Set'::text NOT NULL,
    name text NOT NULL,
    "from" text,
    "to" text
);


ALTER TABLE "MetaPreferences_DataTypes" OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 25114)
-- Name: MetaPreferences_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "MetaPreferences_History" (
    key uuid NOT NULL,
    topic_history_key uuid NOT NULL,
    type text,
    name text NOT NULL,
    value text NOT NULL
);


ALTER TABLE "MetaPreferences_History" OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 25120)
-- Name: Site_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Site_History" (
    key uuid NOT NULL,
    site_key uuid NOT NULL,
    site_name text NOT NULL,
    timestamp_epoch integer NOT NULL,
    user_key uuid NOT NULL,
    session_id character varying,
    session_key character varying,
    start_time bigint,
    finish_time bigint
);


ALTER TABLE "Site_History" OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 25126)
-- Name: Sites; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Sites" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_site_name text DEFAULT 'Need a real site name'::text,
    local_preferences uuid NOT NULL,
    default_preferences uuid NOT NULL,
    site_home uuid NOT NULL,
    admin_user uuid NOT NULL,
    admin_group uuid NOT NULL,
    system_web uuid NOT NULL,
    trash_web uuid NOT NULL,
    home_web uuid NOT NULL,
    guest_user uuid NOT NULL,
    product_id uuid,
    public_key character varying,
    generator character varying,
    link_to_previous uuid
);


ALTER TABLE "Sites" OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 25134)
-- Name: User_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "User_History" (
    key uuid NOT NULL,
    first_name text,
    last_name text,
    login_name text NOT NULL,
    "cUID" text,
    password character varying NOT NULL,
    user_key uuid NOT NULL,
    change_user_key uuid NOT NULL,
    timestamp_epoch integer NOT NULL,
    email text,
    pin_number integer,
    country text DEFAULT 'Japan'::text,
    callback_number character varying,
    gpg_key character varying,
    email_password character varying,
    CONSTRAINT pin_number_range CHECK (((0 < pin_number) AND (pin_number < 99999999)))
);


ALTER TABLE "User_History" OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 25142)
-- Name: Users; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Users" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_login_name text DEFAULT 'name me something nice'::text,
    user_topic_key uuid NOT NULL,
    site_key uuid NOT NULL,
    csr character varying,
    crt character varying
);


ALTER TABLE "Users" OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 25150)
-- Name: Web_History; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Web_History" (
    key uuid NOT NULL,
    web_key uuid NOT NULL,
    timestamp_epoch integer NOT NULL,
    user_key uuid NOT NULL,
    web_name text NOT NULL
);


ALTER TABLE "Web_History" OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 25156)
-- Name: Webs; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE "Webs" (
    key uuid NOT NULL,
    link_to_latest uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid,
    current_web_name text DEFAULT 'Name me something nice'::text,
    site_key uuid NOT NULL,
    web_preferences uuid NOT NULL,
    web_home uuid NOT NULL
);


ALTER TABLE "Webs" OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 25164)
-- Name: email; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE email (
    message_id character varying NOT NULL,
    user_agent character varying,
    mime_version character varying,
    content_type character varying,
    content_transfer_encoding character varying,
    receiveds text,
    email_references text,
    in_reply_to text
);


ALTER TABLE email OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 25170)
-- Name: email_topic_history; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE email_topic_history (
    message_id character varying NOT NULL,
    topic_history_key uuid NOT NULL,
    site_key uuid
);


ALTER TABLE email_topic_history OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 25176)
-- Name: versions; Type: TABLE; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE TABLE versions (
    table_name text NOT NULL,
    table_version integer
);


ALTER TABLE versions OWNER TO postgres;

--
-- TOC entry 2454 (class 2606 OID 32939)
-- Name: th_key; Type: CONSTRAINT; Schema: foswiki; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY "Topic_History"
    ADD CONSTRAINT th_key PRIMARY KEY (key);


--
-- TOC entry 2448 (class 2606 OID 32941)
-- Name: topic_key_1; Type: CONSTRAINT; Schema: foswiki; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY "Topics"
    ADD CONSTRAINT topic_key_1 PRIMARY KEY (key);


--
-- TOC entry 2473 (class 2606 OID 32943)
-- Name: user_table_key; Type: CONSTRAINT; Schema: foswiki; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY "Users"
    ADD CONSTRAINT user_table_key PRIMARY KEY (key);


--
-- TOC entry 2444 (class 1259 OID 32948)
-- Name: blobkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX blobkey_index ON "Blob_Store" USING btree (key);


--
-- TOC entry 2445 (class 1259 OID 32949)
-- Name: blobnumber_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX blobnumber_index ON "Blob_Store" USING btree (number_vector);


--
-- TOC entry 2446 (class 1259 OID 32950)
-- Name: blobvector_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX blobvector_index ON "Blob_Store" USING gin (value_vector);


--
-- TOC entry 2462 (class 1259 OID 32951)
-- Name: dfdatadef_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdatadef_index ON "Dataform_Data_Field" USING btree (definition_field_key);


--
-- TOC entry 2463 (class 1259 OID 32952)
-- Name: dfdatakey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX dfdatakey_index ON "Dataform_Data_Field" USING btree (field_key);


--
-- TOC entry 2464 (class 1259 OID 32953)
-- Name: dfdatathkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdatathkey_index ON "Dataform_Data_Field" USING btree (topic_history_key);


--
-- TOC entry 2465 (class 1259 OID 32954)
-- Name: dfdatavalue_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdatavalue_index ON "Dataform_Data_Field" USING btree (field_value);


--
-- TOC entry 2466 (class 1259 OID 32955)
-- Name: dfdeffieldname_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdeffieldname_index ON "Dataform_Definition_Field" USING btree (field_name);


--
-- TOC entry 2467 (class 1259 OID 32956)
-- Name: dfdefkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdefkey_index ON "Dataform_Definition_Field" USING btree (field_key);


--
-- TOC entry 2468 (class 1259 OID 32957)
-- Name: dfdefthkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX dfdefthkey_index ON "Dataform_Definition_Field" USING btree (topic_history_key);


--
-- TOC entry 2469 (class 1259 OID 32958)
-- Name: mph_key_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX mph_key_index ON "MetaPreferences_History" USING btree (key);


--
-- TOC entry 2470 (class 1259 OID 32959)
-- Name: mph_name_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX mph_name_index ON "MetaPreferences_History" USING btree (name);


--
-- TOC entry 2471 (class 1259 OID 32960)
-- Name: mph_thkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX mph_thkey_index ON "MetaPreferences_History" USING btree (topic_history_key);


--
-- TOC entry 2455 (class 1259 OID 32961)
-- Name: thcontent_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thcontent_index ON "Topic_History" USING btree (topic_content);


--
-- TOC entry 2456 (class 1259 OID 32962)
-- Name: thkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX thkey_index ON "Topic_History" USING btree (key);


--
-- TOC entry 2457 (class 1259 OID 32963)
-- Name: thname_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thname_index ON "Topic_History" USING btree (topic_name);


--
-- TOC entry 2458 (class 1259 OID 32964)
-- Name: thtime_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thtime_index ON "Topic_History" USING btree (timestamp_epoch);


--
-- TOC entry 2459 (class 1259 OID 32965)
-- Name: thtopickey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thtopickey_index ON "Topic_History" USING btree (topic_key);


--
-- TOC entry 2460 (class 1259 OID 32966)
-- Name: thuser_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thuser_index ON "Topic_History" USING btree (user_key);


--
-- TOC entry 2461 (class 1259 OID 32967)
-- Name: thweb_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX thweb_index ON "Topic_History" USING btree (web_key);


--
-- TOC entry 2449 (class 1259 OID 32968)
-- Name: topickey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX topickey_index ON "Topics" USING btree (key);


--
-- TOC entry 2450 (class 1259 OID 32969)
-- Name: topicl2l_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX topicl2l_index ON "Topics" USING btree (link_to_latest);


--
-- TOC entry 2451 (class 1259 OID 32970)
-- Name: topicname_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX topicname_index ON "Topics" USING btree (current_topic_name);


--
-- TOC entry 2452 (class 1259 OID 32971)
-- Name: topicweb_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX topicweb_index ON "Topics" USING btree (current_web_key);


--
-- TOC entry 2474 (class 1259 OID 32972)
-- Name: webkey_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE UNIQUE INDEX webkey_index ON "Webs" USING btree (key);


--
-- TOC entry 2475 (class 1259 OID 32973)
-- Name: webname_index; Type: INDEX; Schema: foswiki; Owner: postgres; Tablespace: 
--

CREATE INDEX webname_index ON "Webs" USING btree (current_web_name);


--
-- TOC entry 2478 (class 2620 OID 32974)
-- Name: current_attachment_updater; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER current_attachment_updater AFTER INSERT ON "Attachment_History" FOR EACH ROW EXECUTE PROCEDURE current_attachment_updater();


--
-- TOC entry 2482 (class 2620 OID 32975)
-- Name: current_group_updater; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER current_group_updater AFTER INSERT ON "Group_History" FOR EACH ROW EXECUTE PROCEDURE current_group_updater();


--
-- TOC entry 2485 (class 2620 OID 32976)
-- Name: current_user_updater; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER current_user_updater AFTER INSERT ON "User_History" FOR EACH ROW EXECUTE PROCEDURE current_user_updater();


--
-- TOC entry 2480 (class 2620 OID 32977)
-- Name: group_user_membership_delete_update_trigger; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER group_user_membership_delete_update_trigger AFTER UPDATE ON "Topics" FOR EACH ROW EXECUTE PROCEDURE group_user_membership_deleter_update();


--
-- TOC entry 2483 (class 2620 OID 32978)
-- Name: group_user_membership_update_trigger; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER group_user_membership_update_trigger AFTER INSERT ON "Links" FOR EACH ROW EXECUTE PROCEDURE group_user_membership_updater();


--
-- TOC entry 2479 (class 2620 OID 32979)
-- Name: redundant_file_store_updater; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER redundant_file_store_updater AFTER INSERT ON "Attachment_History" FOR EACH ROW EXECUTE PROCEDURE file_store_updater();


--
-- TOC entry 2484 (class 2620 OID 32980)
-- Name: site_history_insert_updater_trigger; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER site_history_insert_updater_trigger AFTER INSERT ON "Site_History" FOR EACH ROW EXECUTE PROCEDURE current_site_updater();


--
-- TOC entry 2481 (class 2620 OID 32981)
-- Name: topic_history_insert_updater_trigger; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER topic_history_insert_updater_trigger AFTER INSERT ON "Topic_History" FOR EACH ROW EXECUTE PROCEDURE current_topic_updater();


--
-- TOC entry 2486 (class 2620 OID 32982)
-- Name: web_history_insert_updater_trigger; Type: TRIGGER; Schema: foswiki; Owner: postgres
--

CREATE TRIGGER web_history_insert_updater_trigger AFTER INSERT ON "Web_History" FOR EACH ROW EXECUTE PROCEDURE current_web_updater();


--
-- TOC entry 2476 (class 2606 OID 32983)
-- Name: th_topic_key; Type: FK CONSTRAINT; Schema: foswiki; Owner: postgres
--

ALTER TABLE ONLY "Topic_History"
    ADD CONSTRAINT th_topic_key FOREIGN KEY (topic_key) REFERENCES "Topics"(key) DEFERRABLE;


--
-- TOC entry 2477 (class 2606 OID 32988)
-- Name: th_user_key; Type: FK CONSTRAINT; Schema: foswiki; Owner: postgres
--

ALTER TABLE ONLY "Topic_History"
    ADD CONSTRAINT th_user_key FOREIGN KEY (user_key) REFERENCES "Users"(key) DEFERRABLE;


-- Completed on 2015-09-19 16:59:13 JST

--
-- PostgreSQL database dump complete
--

