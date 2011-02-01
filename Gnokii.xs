#include <gnokii.h>
#include <gnokii/common.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_sv_2pv_flags
#include "ppport.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

#undef DEBUG_MODULE

#ifndef false
#  define false 0
#  endif

#ifndef true
#  define true 1
#  endif

#ifndef gn_bool
#  define gn_bool int
#  endif

#define unless(e) if (!(e))

#define _hvstore(hash,key,sv) (void)hv_store (hash, key, strlen (key), sv, 0)
#define hv_puts(hash,key,str) _hvstore (hash, key, newSVpv ((char *)(str), 0))
#define hv_putS(hash,key,s,l) _hvstore (hash, key, newSVpv ((char *)(s),   l))
#define hv_puti(hash,key,num) _hvstore (hash, key, newSViv (num))
#define hv_putn(hash,key,num) _hvstore (hash, key, newSVnv (num))
#define hv_putr(hash,key,ref) _hvstore (hash, key, newRV_inc ((SV *)(ref)))
#define av_addr(list,ref)     av_push  (list,      newRV_inc ((SV *)(ref)))

#define XS_RETURNr(rv) {\
    ST (0) = sv_2mortal (newRV_noinc ((SV *)(rv)));\
    XSRETURN (1);\
    }
#define XS_RETURNi(i) {\
    ST (0) = sv_2mortal (newSViv (i));\
    XSRETURN (1);\
    }

#define GSMDATE_TO_TM(KEY,GSM,HASH) {\
    time_t rt;\
    struct tm t;\
    char   s[21];\
\
    t.tm_year  = GSM.year;\
    if (t.tm_year  > 1900)\
	t.tm_year -= 1900;\
    t.tm_mon   = GSM.month - 1;\
    t.tm_mday  = GSM.day;\
    t.tm_hour  = GSM.hour;\
    t.tm_min   = GSM.minute;\
    t.tm_sec   = GSM.second;\
    t.tm_isdst =-1;\
    t.tm_wday  = 0;\
    t.tm_yday  = 0;\
    rt = mktime (&t);\
    hv_puti (HASH, "timestamp", rt);\
    sprintf (s, "%04d-%02d-%02d %02d:%02d:%02d", GSM.year, GSM.month, GSM.day, GSM.hour, GSM.minute, GSM.second);\
    hv_puts (HASH, KEY,         s);\
    }

#define HASH_TO_GSMDT(GSMDT,LOCALTIME) {\
    struct tm *t;\
    Newx (t, 1, struct tm);\
    t = localtime (LOCALTIME);\
    GSMDT->year   = 1900 + t->tm_year;\
    GSMDT->month  = t->tm_mon + 1;\
    GSMDT->day    = t->tm_mday;\
    GSMDT->hour   = t->tm_hour;\
    GSMDT->minute = t->tm_min;\
    GSMDT->second = t->tm_sec;\
    }

static int not_here (char *s)
{
    croak ("%s not implemented on this architecture", s);
    return (-1);
    } /* not_here */

static double constant (char *name, int len, int arg)
{
    errno = EINVAL;
    return 0;
    } /* constant */

typedef HV HvObject;
typedef AV AvObject;

static struct gn_statemachine	*state;
static gn_data			*data;
static char			*configfile  = NULL;
static char			*configmodel = NULL;
#ifdef DEBUG_MODULE
static int			opt_v = 1;
#else
static int			opt_v = 0;
#endif
static gn_error			op_error = 0;

gn_memory_status SIMMemoryStatus   = {GN_MT_SM, 0, 0};
gn_memory_status PhoneMemoryStatus = {GN_MT_ME, 0, 0};
gn_memory_status DC_MemoryStatus   = {GN_MT_DC, 0, 0};
gn_memory_status EN_MemoryStatus   = {GN_MT_EN, 0, 0};
gn_memory_status FD_MemoryStatus   = {GN_MT_FD, 0, 0};
gn_memory_status LD_MemoryStatus   = {GN_MT_LD, 0, 0};
gn_memory_status MC_MemoryStatus   = {GN_MT_MC, 0, 0};
gn_memory_status ON_MemoryStatus   = {GN_MT_ON, 0, 0};
gn_memory_status RC_MemoryStatus   = {GN_MT_RC, 0, 0};

static int set_error (HV *h, int n, char *s)
{
    unless (s) s = gn_error_print (n);
    if (n) warn ("%s\n", s);
    if (h) hv_puts (h, "ERROR", s);
    return (n);
    } /* set_error */
#define set_errori(n) set_error (self, n, NULL);
#define set_errors(s) set_error (self, 1, s);
#define clear_err()   set_error (self, 0, "no error / no data");

static void busterminate (void)
{
    if (state) {
	gn_lib_phone_close (state);
	gn_lib_phoneprofile_free (&state);
	gn_lib_library_free ();
	state = NULL;
	}
    } /* busterminate */

static int businit (HV *self)
{
    gn_error err;

    if (opt_v) warn ("Starting businit ...\n");

    err = gn_lib_phoneprofile_load_from_file (configfile, configmodel, &state);
    unless (err == GN_ERR_NONE) {
	set_errori (err);
	if (configfile)
	    warn (_("File: %s\n"), configfile);
	if (configmodel)
	    warn (_("Phone section: [phone_%s]\n"), configmodel);
	return 2;
	}

    if (opt_v) warn ("Phone profile loaded\n");
    /* register cleanup function */
    atexit (busterminate);
    /* signal(SIGINT, bussignal); */

    if (opt_v) warn ("Opening phone ...\n");
    unless ((err = gn_lib_phone_open (state)) == GN_ERR_NONE) {
	set_errori (err);
	return 2;
	}

    clear_err ();
    data = &state->sm_data;
    return 0;
    } /* businit */

static void clear_data (void)
{
    gn_data_clear (data);
    } /* clear_data */

static int gn_sm_func (HV *self, int op)
{
    char *s_err;

    op_error = gn_sm_functions (op, data, state);
    if (op_error == GN_ERR_NONE) {
	clear_err ();
	return (1);
	}

    s_err = gn_error_print (op_error);
    warn ("OP ERROR: %s\n", s_err);
    hv_puts (self, "ERROR", s_err);
    return (0);
    } /* gn_sm_func */

static char *filetype2str (int type)
{
    switch (type) {
	case GN_FT_None:        return ("None");
	case GN_FT_NOL:         return ("NOL");
	case GN_FT_NGG:         return ("NGG");
	case GN_FT_NSL:         return ("NSL");
	case GN_FT_NLM:         return ("NLM");
	case GN_FT_BMP:         return ("BMP");
	case GN_FT_OTA:         return ("OTA");
	case GN_FT_XPMF:        return ("XPMF");
	case GN_FT_RTTTL:       return ("RTTTL");
	case GN_FT_OTT:         return ("OTT");
	case GN_FT_MIDI:        return ("MIDI");
	case GN_FT_NOKRAW_TONE: return ("NOKRAW_TONE");
	case GN_FT_GIF:         return ("GIF");
	case GN_FT_JPG:         return ("JPG");
	case GN_FT_MID:         return ("MID");
	case GN_FT_NRT:         return ("NRT");
	case GN_FT_PNG:         return ("PNG");
	default:                return ("unknown");
	}
    } /* filetype2str */

static gn_gsm_number_type get_number_type (const char *number)
{
    gn_gsm_number_type type = GN_GSM_NUMBER_Unknown;

    unless (number)	return type;
    if (*number == '+') {
	type = GN_GSM_NUMBER_International;
	number++;
	}
    while (*number) {
	unless (isdigit (*number))
	    return GN_GSM_NUMBER_Alphanumeric;
	number++;
	}
    return type;
    } /* get_number_type */

static AV *walk_tree (HV *self, char *path, gn_file_list *fl)
{
    AV	*t = newAV ();
    int	i;

    if (opt_v) warn ("Traverse path %s\n", path);

    for (i = 0; i < fl->file_count; i++) {
	HV	*f = newHV ();
	char	date[32], full_name[512];
	gn_file	*fi = fl->files[i];
	int	is_file;

	hv_puts (f, "type",      filetype2str (fi->filetype));
	hv_puts (f, "name",      fi->name);
	sprintf (date, "%04d-%02d-%02d %02d:%02d:%02d",
	    fi->year, fi->month, fi->day, fi->hour, fi->minute, fi->second);
	hv_puts (f, "date",      date);
	hv_puti (f, "size",      fi->file_length);
	hv_puti (f, "folder_id", fi->folderId);
	hv_puts (f, "file",      fi->file);

	snprintf (full_name, 512, "%s\\%s", path, fi->name);
	if (*(fi->name)) {
	    gn_file ff;

	    clear_data ();
	    Zero (&ff, 1, ff);
	    strcpy (ff.name, full_name);
	    data->file = &ff;
	    if (gn_sm_func (self, GN_OP_GetFileId)) {
		char buf[16];
		sprintf (buf, "%02x.%02x.%02x.%02x.%02x.%02x",
		    ff.id[0], ff.id[1], ff.id[2], ff.id[3], ff.id[4], ff.id[5]);
		hv_puts (f, "id", buf);
		}
	    }

	if (fi->file_length == 0 && *(fi->name)) {	/* dir ? */
	    gn_file_list	dl;

	    clear_data ();
	    Zero (&dl, 1, dl);
	    sprintf (dl.path, "%s\\*", full_name);
	    data->file_list = &dl;
	    if (gn_sm_func (self, GN_OP_GetFileList) && dl.file_count > 0) {
		hv_puts (f, "path",		full_name);
		hv_puti (f, "file_count",	dl.file_count);
		hv_puti (f, "dir_size",		dl.size);
		hv_putr (f, "tree", walk_tree (self, full_name, &dl));
		}
	    }

	free (fi);
	av_addr (t, f);
	}
    return (t);
    } /* walk_tree */

MODULE = GSM::Gnokii		PACKAGE = GSM::Gnokii

void
_Initialize (self)
    HV		*self;

  PPCODE:
    int		err;

    opt_v = SvIV (*hv_fetch (self, "verbose", 7, 0));

    if (opt_v) warn ("initialise ({ ... })\n");

    unless (gn_lib_init () == GN_ERR_NONE)
	croak (_("Failed to initialize libgnokii.\n"));

    hv_puts (self, "libgnokii_version", LIBGNOKII_VERSION_STRING);

    err = businit (self);
    unless (err == GN_ERR_NONE)
	croak ("Init failed");

    XSRETURN (err);
    /* _Initialise */

void
GetPhonebook (self, mem_type, start, end)
    HvObject		*self;
    char		*mem_type;
    int			start;
    int			end;

  PPCODE:
    gn_phonebook_entry	*entry;
    int			mt, i, j;
    AV			*pb;

    if (opt_v) warn ("GetPhonebook (%s, %d, %d)\n", mem_type, start, end);

    clear_data ();

    if (start < 0 || start > 255) {
	set_errors ("phonebook location should be in valid range 0..255");
	XSRETURN_UNDEF;
	}

    mt = gn_str2memory_type (mem_type);
    if (mt == GN_MT_XX) {
	char s_err[80];
	sprintf (s_err, "ERROR: Unknown memory type '%s' (use IN, ME, SM, ...)", mem_type);
	set_errors (s_err);
	XSRETURN_UNDEF;
	}

    if (end <= 0 || end > 255) {
	gn_memory_status ms = {mt, 0, 0};
	data->memory_status = &ms;
	if (gn_sm_func (self, GN_OP_GetMemoryStatus)) {
	    end = ms.used + 1;
	    if (end < start)
		end = start;
	    }
	}

    pb = newAV ();
    Newxz (entry, 1, gn_phonebook_entry);
    data->phonebook_entry = entry;
    for (i = start; i <= end; i++) {
	HV *abe = newHV ();

	Zero (entry, 1, gn_phonebook_entry);
	entry->memory_type = gn_str2memory_type (mem_type);
	memset (entry->name,   ' ', GN_PHONEBOOK_NAME_MAX_LENGTH   + 1);
	memset (entry->number, ' ', GN_PHONEBOOK_NUMBER_MAX_LENGTH + 1);

	if (opt_v) warn ("Reading %s Entry %d\n", mem_type, i);

	entry->location       = i;
	entry->caller_group   = i;
	data->phonebook_entry = entry;
	op_error = gn_sm_functions (GN_OP_ReadPhonebook, data, state);
	if (op_error == GN_ERR_NONE && ! entry->empty) {
#ifdef DEBUG_MODULE
	    printf (
	      "Name:    %s\n"
	      "Number:  %s\n"
	      "Group:   %d\n"
	      "Location %d\n",
		  entry->name, entry->number, entry->caller_group,
		  entry->location);
#endif
	    hv_puts (abe, "memorytype", mem_type);
	    hv_puti (abe, "location",   entry->location);
	    hv_puts (abe, "number",     entry->number);
	    hv_puts (abe, "name",       entry->name);
	    hv_puti (abe, "group",      entry->caller_group);
	    if (entry->person.has_person) {
		HV *p = newHV ();
		if (entry->person.honorific_prefixes[0])
		    hv_puts (p, "formal_name",      entry->person.honorific_prefixes);
		if (entry->person.honorific_suffixes[0])
		    hv_puts (p, "formal_suffix",    entry->person.honorific_suffixes);
		if (entry->person.given_name[0])
		    hv_puts (p, "given_name",       entry->person.given_name);
		if (entry->person.family_name[0])
		    hv_puts (p, "family_name",      entry->person.family_name);
		if (entry->person.additional_names[0])
		    hv_puts (p, "additional_names", entry->person.additional_names);
		_hvstore (abe, "person", newRV_inc ((SV *)p));
		}
	    if (entry->address.has_address) {
		HV *a = newHV ();
		if (entry->address.post_office_box[0])
		    hv_puts (a, "postal",           entry->address.post_office_box);
		if (entry->address.extended_address[0])
		    hv_puts (a, "extended_address", entry->address.extended_address);
		if (entry->address.street[0])
		    hv_puts (a, "street",           entry->address.street);
		if (entry->address.city[0])
		    hv_puts (a, "city",             entry->address.city);
		if (entry->address.state_province[0])
		    hv_puts (a, "state_province",   entry->address.state_province);
		if (entry->address.zipcode[0])
		    hv_puts (a, "zipcode",          entry->address.zipcode);
		if (entry->address.country[0])
		    hv_puts (a, "country",          entry->address.country);
		hv_putr (abe, "address", a);
		}
	    for (j = 0; j < entry->subentries_count; j++) {
		char str[32];

		switch (entry->subentries[j].entry_type) {
		    /* From _raw ... */
		    case GN_PHONEBOOK_ENTRY_Birthday:
			sprintf (str, "%4d-%02d-%02d",
			    entry->subentries[j].data.date.year, entry->subentries[j].data.date.month,
			    entry->subentries[j].data.date.day);
			hv_puts (abe, "birthday",     str);
			break;

		    case GN_PHONEBOOK_ENTRY_Date:
			sprintf (str, "%4d-%02d-%02d %02d:%02d:%02d",
			    entry->subentries[j].data.date.year,   entry->subentries[j].data.date.month,
			    entry->subentries[j].data.date.day,    entry->subentries[j].data.date.hour,
			    entry->subentries[j].data.date.minute, entry->subentries[j].data.date.second);
			hv_puts (abe, "date",         str);
			break;
#if LIBGNOKII_VERSION_MAJOR >= 6
		    case GN_PHONEBOOK_ENTRY_ExtGroup:
			hv_puti (abe, "ext_group",    entry->subentries[j].data.id);
			break;
#endif

		    /* from vcard */
		    case GN_PHONEBOOK_ENTRY_Email:
			hv_puts (abe, "e_mail",       entry->subentries[j].data.number);
			break;

		    case GN_PHONEBOOK_ENTRY_Postal:
			hv_puts (abe, "home_address", entry->subentries[j].data.number);
			break;

		    case GN_PHONEBOOK_ENTRY_Note:
			hv_puts (abe, "note",         entry->subentries[j].data.number);
			break;

		    case GN_PHONEBOOK_ENTRY_Number:
			switch (entry->subentries[j].number_type) {
			    case GN_PHONEBOOK_NUMBER_Home:
				hv_puts (abe, "tel_home",    entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_Mobile:
				hv_puts (abe, "tel_cell",    entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_Fax:
				hv_puts (abe, "tel_fax",     entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_Work:
				hv_puts (abe, "tel_work",    entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_None:
				if (strcmp (entry->subentries[j].data.number, entry->number))
				    hv_puts (abe, "tel_none", entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_Common:
				hv_puts (abe, "tel_common",  entry->subentries[j].data.number);
				break;

			    case GN_PHONEBOOK_NUMBER_General:
				hv_puts (abe, "tel_general", entry->subentries[j].data.number);
				break;

			    default:
				sprintf (str, "tel_%03d_%03d",
				    entry->subentries[j].number_type, entry->subentries[j].id);
				hv_puts (abe, str, entry->subentries[j].data.number);
				break;
			    }
			break;

		    case GN_PHONEBOOK_ENTRY_URL:
			hv_puts (abe, "url", entry->subentries[j].data.number);
			break;

		    default:
			sprintf (str, "item_%04d_%03d_%03d", entry->subentries[j].entry_type,
			    entry->subentries[j].number_type, entry->subentries[j].id);
			hv_puts (abe, str, entry->subentries[j].data.number);
			break;
		    }
		}
	    av_addr (pb, abe);
	    }
#ifdef DEBUG_MODULE
	else
	    warn ("DEF: %s;%s;%s;%d;%d;%d\n", entry->name, entry->number,
		mem_type, entry->location, entry->caller_group,
		entry->subentries_count);
#endif
	}

    XS_RETURNr (pb);
    /* GetPhonebook */

void
GetSMS (self, mem_type, location)
    HvObject		*self;
    char		*mem_type;
    int			location;

  PPCODE:
    gn_sms		*message;
    gn_sms_folder	*folder;
    gn_sms_folder_list	*folderlist;
    int			i;

    if (opt_v) warn ("GetSMS (%s, %d)\n", mem_type, location);

    clear_data ();
    Newxz (message, 1, gn_sms);

    message->memory_type = gn_str2memory_type (mem_type);
    if (message->memory_type == GN_MT_XX) {
	char s_err[80];
	sprintf (s_err, "ERROR: Unknown memory type '%s' (use IN, ME, SM, ...)", mem_type);
	set_errors (s_err);
	XSRETURN_UNDEF;
	}

    message->memory_type = gn_str2memory_type (mem_type);
    message->number      = location;
    Newxz (folder,     1, gn_sms_folder);
    /*folder->FolderID = 2;*/
    Newxz (folderlist, 1, gn_sms_folder_list);
    data->sms             = message;
    data->sms_folder      = folder;
    data->sms_folder_list = folderlist;
    if (gn_sms_get (data, state) == GN_ERR_NONE) {
	HV *sms = newHV ();

	hv_puts (sms, "memorytype", mem_type);
	hv_puti (sms, "location",   location);
	switch (message->type) {
	    case 0: /* normal SMS */
		hv_puts (sms, "text",      message->user_data[0].u.text);
		hv_puts (sms, "sender",    message->remote.number);
		hv_puts (sms, "smsc",      message->smsc.number);
		GSMDATE_TO_TM ("smscdate", message->smsc_time, sms);
		GSMDATE_TO_TM ("date",     message->time,      sms);
		switch (message->status) {
		    case GN_SMS_Unknown: hv_puts (sms, "status", "unknown"); break;
		    case GN_SMS_Read:    hv_puts (sms, "status", "read");    break;
		    case GN_SMS_Unread:  hv_puts (sms, "status", "unread");  break;
		    case GN_SMS_Sent:    hv_puts (sms, "status", "sent");    break;
		    case GN_SMS_Unsent:  hv_puts (sms, "status", "unsent");  break;
		    }
		break;

	    default:
		warn ("SMS message type '%s' not yet dealt with\n", gn_sms_message_type2str (message->type));
	    }
	unless (message->udh.number)
	    message->udh.udh[0].type = GN_SMS_UDH_None;

	switch (message->udh.udh[0].type) {
	    case GN_SMS_UDH_None:
		break;

	    case GN_SMS_UDH_ConcatenatedMessages:
		hv_puti (sms, "concat_current", message->udh.udh[0].u.concatenated_short_message.current_number);
		hv_puti (sms, "concat_max",     message->udh.udh[0].u.concatenated_short_message.maximum_number);
		break;

	    default:
		warn ("Warning: GetSMS: Unhandled message type of '%d': continuing\n", message->udh.udh[0].type);
		break;
	    }
#ifdef DEBUG_MODULE
	warn ("Type:         %d\n"
	      "DataType:     %d\n"
	      "Text:         %s\n"
	      "SMSCTime.Year %d\n"
	      "FolderCount:  %d\n"
	      "Foldername:   %s\n",
		message->type, message->user_data[0].type,
		message->user_data[0].u.text, message->smsc_time.year,
		data->sms_folder_list->number, data->sms_folder->name);
#endif
	for (i = 0; i < data->sms_folder_list->number; i++) {
#ifdef DEBUG_MODULE
	    int j;
	    warn ("ID:       %d\n"
		  "Name:     %s\n"
		  "Number:   %d\n",
		    data->sms_folder_list->folder_id[i],
		    data->sms_folder_list->folder[i].name,
		    data->sms_folder_list->folder[i].number);
	    for (j = 0; j < data->sms_folder_list->folder[i].number; j++)
		warn ("\tLoca: %d\n", data->sms_folder_list->folder[i].locations[j]);
#endif
	    }
	XS_RETURNr (sms);
	}
    XSRETURN_UNDEF;
    /* GetSMS */

int
DeleteSMS (self, memtype, location, foldername)
    HvObject		*self;
    char		*memtype;
    int			location;
    char		*foldername;

  PREINIT:
    gn_sms		message;
    gn_sms_folder	folder;
    gn_sms_folder_list	folderlist;

  CODE:
    clear_data ();
    Zero (&message,    1, message);
    Zero (&folder,     1, folder);
    Zero (&folderlist, 1, folderlist);
    message.memory_type = gn_str2memory_type (memtype);
    if (message.memory_type == GN_MT_XX)
	warn (_("Unknown memory type %s (use ME, SM, ...)\n"), memtype);
    else {
	message.number        = location;
	data->sms             = &message;
	data->sms_folder      = &folder;
	data->sms_folder_list = &folderlist;
	RETVAL = gn_sms_delete (data, state);
	}

  OUTPUT:
    RETVAL

void
GetDateTime (self)
    HvObject		*self;

  PPCODE:
    gn_timestamp	date_time;

    if (opt_v) warn ("GetDateTime ()\n");

    clear_data ();
    data->datetime = &date_time;
    if (gn_sm_func (self, GN_OP_GetDateTime)) {
	HV *dt = newHV ();
	GSMDATE_TO_TM ("date", date_time, dt);
	XS_RETURNr (dt);
	}

    XSRETURN_UNDEF;
    /* GetDateTime */

void
GetDisplayStatus (self)
    HvObject	*self;

  PPCODE:
    int		status = 0;

    if (opt_v) warn ("GetDisplayStatus ()\n");

    clear_data ();
    data->display_status = &status;
    if (gn_sm_func (self, GN_OP_GetDisplayStatus)) {
	HV *ds = newHV ();

	hv_puti (ds, "call_in_progress", status & (1 << GN_DISP_Call_In_Progress) ? 1 : 0);
	hv_puti (ds, "unknown",          status & (1 << GN_DISP_Unknown)          ? 1 : 0);
	hv_puti (ds, "unread_SMS",       status & (1 << GN_DISP_Unread_SMS)       ? 1 : 0);
	hv_puti (ds, "voice_call",       status & (1 << GN_DISP_Voice_Call)       ? 1 : 0);
	hv_puti (ds, "fax_call_active",  status & (1 << GN_DISP_Fax_Call)         ? 1 : 0);
	hv_puti (ds, "data_call_active", status & (1 << GN_DISP_Data_Call)        ? 1 : 0);
	hv_puti (ds, "keyboard_lock",    status & (1 << GN_DISP_Keyboard_Lock)    ? 1 : 0);
	hv_puti (ds, "sms_storage_full", status & (1 << GN_DISP_SMS_Storage_Full) ? 1 : 0);
	XS_RETURNr (ds);
	}

    XSRETURN_UNDEF;
    /* GetDisplayStatus */

void
GetSMSFolderList (self)
    HvObject		*self;

  PPCODE:
    gn_sms_folder_list	folderlist;
    AV			*fl;
    int			i;

    if (opt_v) warn ("GetSMSFolderList ()\n");

    clear_data ();
    Zero (&folderlist, 1, folderlist);
    data->sms_folder_list = &folderlist;
    unless (gn_sm_func (self, GN_OP_GetSMSFolders))
	XSRETURN_UNDEF;

    fl = newAV ();
    for (i = 0; i < folderlist.number; i++) {
	HV *f = newHV ();
	if (opt_v) warn (" + GetSMSFolderStatus (%d)", i);
	hv_puti (f, "location", i);
	hv_puts (f, "memorytype", gn_memory_type2str (folderlist.folder_id[i]));
	data->sms_folder = folderlist.folder + i;
	if (gn_sm_func (self, GN_OP_GetSMSFolderStatus)) {
	    hv_puts (f, "name",  folderlist.folder[i].name);
	    hv_puti (f, "count", folderlist.folder[i].number);
	    }
	av_addr (fl, f);
	}
    XS_RETURNr (fl);
    /* GetSMSFolderList */

void
GetSpeedDial (self, location)
    HvObject		*self;
    int			location;

  PPCODE:
    gn_speed_dial	*speeddial;
    SV			**ssv;

    if (opt_v) warn ("Get Speed Dial %d\n", location);

    if (location < 0)
	croak ("Speed dial number should be >= 0\n");

    clear_data ();
    Newxz (speeddial, 1, gn_speed_dial);
    speeddial->number = location;
    data->speed_dial  = speeddial;
    if (gn_sm_func (self, GN_OP_GetSpeedDial)) {
	HV *sd = newHV ();

	hv_puti (sd, "number",   speeddial->number);
	hv_puti (sd, "location", speeddial->location);
	ssv = av_fetch ((AV *)SvRV (*hv_fetch (self, "MEMORY_TYPES", 12, 0)), speeddial->memory_type, 0);
	hv_puts (sd, "memory",   SvPV_nolen (*ssv));
	XS_RETURNr (sd);
	}
    XSRETURN_UNDEF;
    /* GetSpeedDial */

void
GetIMEI (self)
    HvObject	*self;

  PPCODE:
    char	imei[64], model[64], rev[64], manufacturer[64];

    if (opt_v) warn ("GetIMEI ()\n");

    clear_data ();
    Zero (imei,         64, char);
    Zero (model,        64, char);
    Zero (rev,          64, char);
    Zero (manufacturer, 64, char);
    data->imei         = imei;
    data->model        = model;
    data->revision     = rev;
    data->manufacturer = manufacturer;
    if (gn_sm_functions (GN_OP_Identify, data, state) == GN_ERR_NONE) {
	HV *ih = newHV ();

	hv_puts (ih, "imei",         data->imei);
	hv_puts (ih, "model",        data->model);
	hv_puts (ih, "revision",     data->revision);
	hv_puts (ih, "manufacturer", data->manufacturer);
	XS_RETURNr (ih);
	}
    XSRETURN_UNDEF;
    /* GetIMEI */

void
GetSecurity (self)
    HvObject		*self;

  PPCODE:
    gn_security_code	sc;

    if (opt_v) warn ("GetSecurity ()\n");

    clear_data ();
    Zero (&sc, 1, sc);
    sc.type = GN_SCT_SecurityCode;
    data->security_code = &sc;
    if (gn_sm_functions (GN_OP_GetSecurityCodeStatus, data, state) == GN_ERR_NONE) {
	char *key;
	HV   *si = newHV ();

	key = "status";
	switch (sc.type) {
	    case GN_SCT_SecurityCode: hv_puts (si, key, "Waiting for Security Code"); break;
	    case GN_SCT_Pin:          hv_puts (si, key, "Waiting for PIN");           break;
	    case GN_SCT_Pin2:         hv_puts (si, key, "Waiting for PIN2");          break;
	    case GN_SCT_Puk:          hv_puts (si, key, "Waiting for PUK");           break;
	    case GN_SCT_Puk2:         hv_puts (si, key, "Waiting for PUK2");          break;
	    case GN_SCT_None:         hv_puts (si, key, "Nothing to enter");          break;
	    default:                  hv_puts (si, key, "Unknown");                   break;
	    }

	if (gn_sm_functions (GN_OP_GetSecurityCode, data, state) == GN_ERR_NONE)
	    hv_puts (si, "security_code", sc.code);

	if (0) {	/* *** stack smashing detected *** */
	    gn_locks_info	li[4];

	    clear_data ();
	    Zero (li, 4, li);
	    data->locks_info = li;
	    if (gn_sm_functions (GN_OP_GetLocksInfo, data, state) == GN_ERR_NONE) {
		char *lock_names[] = {"MCC+MNC", "GID1", "GID2", "MSIN"};
		int  i;
		AV   *lil = newAV ();

		for (i = 0; i < 4; i++) {
		    HV *l = newHV ();
		    hv_puts (l, "name",    lock_names[i]);
		    hv_puts (l, "type",    li[i].userlock ? "user"   : "factory");
		    hv_puts (l, "state",   li[i].closed   ? "closed" : "open");
		    hv_puts (l, "data",    li[i].data);
		    hv_puti (l, "counter", li[i].counter);
		    av_addr (lil, l);
		    }
		hv_putr (si, "locks", lil);
		}
	    }

	XS_RETURNr (si);
	}
    XSRETURN_UNDEF;
    /* GetSecurity */

void
GetLogo (self, logodata)
    HvObject	*self;
    HV		*logodata;

  PPCODE:
    gn_bmp	bitmap;
    char	*type;

    if (opt_v) warn ("GetLogo ({ type => ... })\n");

    clear_data ();
    Zero (&bitmap, 1, gn_bmp);
    type = SvPV_nolen (*hv_fetch (logodata, "type", 4, 0));

	 if (!strcmp (type, "text"))         bitmap.type = GN_BMP_WelcomeNoteText;
    else if (!strcmp (type, "dealer"))       bitmap.type = GN_BMP_DealerNoteText;
    else if (!strcmp (type, "op"))           bitmap.type = GN_BMP_OperatorLogo;
    else if (!strcmp (type, "startup"))      bitmap.type = GN_BMP_StartupLogo;
    else if (!strcmp (type, "caller"))       bitmap.type = GN_BMP_CallerLogo;
    else if (!strcmp (type, "picture"))      bitmap.type = GN_BMP_PictureMessage;
    else if (!strcmp (type, "emspicture"))   bitmap.type = GN_BMP_EMSPicture;
    else if (!strcmp (type, "emsanimation")) bitmap.type = GN_BMP_EMSAnimation;

    if ((bitmap.type == GN_BMP_CallerLogo) &&
	(hv_fetch (logodata, "callerindex", 11, 0) == NULL))
	    bitmap.number = 0; /* das muss noch anders werden */
    data->bitmap = &bitmap;
    if (gn_sm_functions (GN_OP_GetBitmap, data, state) == GN_ERR_NONE) {
	HV *l = newHV ();

	switch (bitmap.type) {
	    case GN_BMP_DealerNoteText:
	    case GN_BMP_WelcomeNoteText:
		hv_puts (l, "text",    bitmap.text);
		break;
	    case GN_BMP_OperatorLogo:
	    case GN_BMP_NewOperatorLogo:
	    case GN_BMP_StartupLogo:
		hv_puts (l, "netcode", bitmap.netcode);
		hv_puts (l, "newname", (char *)gn_network_name_get (bitmap.netcode));
		break;
	    default:
		warn ("Bitmap type %d not yet handled\n", bitmap.type);
	    }
	hv_puts (l, "type",   type);
	hv_putS (l, "bitmap", bitmap.bitmap, bitmap.size);
	hv_puti (l, "size",   bitmap.size);
	hv_puti (l, "height", bitmap.height);
	hv_puti (l, "width",  bitmap.width);
	XS_RETURNr (l);
	}
    XSRETURN_UNDEF;
    /* GetLogo */

void
GetCalendarNotes (self, start, end)
    HvObject		*self;
    int			start;
    int			end;

  PPCODE:
    gn_calnote_list	calendarnoteslist;
    gn_calnote		calendarnote;
    int			i;
    AV			*cnl = newAV ();

    if (opt_v) warn ("GetCalenderNotes (%d, %d)\n", start, end);

    if (start < 0 || start > 255) {
	set_errors ("calendarnote location should be in valid range 0..255");
	XSRETURN_UNDEF;
	}

    if (end <= 0 || end > 255) {
	end = 255;
	/* NYI - find last note location used
	gn_memory_status ms = {mt, 0, 0};
	data->memory_status = &ms;
	if (gn_sm_func (self, GN_OP_GetMemoryStatus)) {
	    end = ms.used + 1;
	    if (end < start)
		end = start;
	    }
	*/
	}

    for (i = start; i <= end; i++) {
	clear_data ();
	calendarnote.location = i;
	data->calnote      = &calendarnote;
	data->calnote_list = &calendarnoteslist;
	if (gn_sm_functions (GN_OP_GetCalendarNote, data, state) == GN_ERR_NONE) {
	    HV *note = newHV ();
	    hv_puti (note, "location", i);
	    switch (calendarnote.type) {
		case GN_CALNOTE_REMINDER:
		    hv_puts (note, "type",   "MISCELLANEOUS");
		    hv_puts (note, "number", calendarnote.phone_number);
		    break;
		case GN_CALNOTE_CALL:
		    hv_puts (note, "type",   "CALL");
		    break;
		case GN_CALNOTE_MEETING:
		    hv_puts (note, "type",   "MEETING");
		    break;
		case GN_CALNOTE_BIRTHDAY:
		    hv_puts (note, "type",   "BIRTHDAY");
		    break;
		case GN_CALNOTE_MEMO:
		    hv_puts (note, "type",   "MEMO");
		    break;
		default:
		    hv_puts (note, "type",   "unknown");
		    break;
		}
	    hv_puts (note, "text", calendarnote.text);
	    if (calendarnote.alarm.timestamp.year)
		GSMDATE_TO_TM ("alarm", calendarnote.alarm.timestamp, note);
	    calendarnote.time.second = 0;
	    calendarnote.time.minute = 0;
	    calendarnote.time.hour   = 0;
	    GSMDATE_TO_TM ("date", calendarnote.time, note);
	    av_addr (cnl, note);
	    }
	}
    XS_RETURNr (cnl);
    /* GetCalendarNotes */

void
GetRingtone (self, location)
    HvObject		*self;
    int			location;

  PPCODE:
    gn_ringtone		ringtone;
    gn_raw_data		rawdata;
    unsigned char	buff[512];

    if (opt_v) warn ("GetRingtone (%d)\n", location);

    Zero (&ringtone, 1, ringtone);
    rawdata.data   = buff;
    rawdata.length = sizeof (buff);
    clear_data ();
    data->ringtone = &ringtone;
    data->raw_data = &rawdata;
    ringtone.location = location;
    if (gn_sm_functions (GN_OP_GetRingtone, data, state) == GN_ERR_NONE) {
	HV		*rt = newHV ();
	int		i   = 2000;
	unsigned char	buffer[2000];

	hv_puti (rt, "location", location);
	hv_puts (rt, "name",     ringtone.name);
	gn_ringtone_pack (&ringtone, buffer, &i);
	hv_puts (rt, "ringtone", buffer);
	hv_puti (rt, "length",   i);
	XS_RETURNr (rt);
	}
    XSRETURN_UNDEF;
    /* GetRingtone */

void
GetRingtoneList (self)
    HV			*self;

  PPCODE:
    gn_ringtone_list	ringtone_list;

    if (opt_v) warn ("GetRingtoneList ()\n");

    clear_data ();
    Zero (&ringtone_list, 1, ringtone_list);
    data->ringtone_list = &ringtone_list;
    if (gn_sm_functions (GN_OP_GetRingtoneList, data, state) == GN_ERR_NONE) {
	HV *rl = newHV ();

	hv_puti (rl, "count",            ringtone_list.count);
	hv_puti (rl, "userdef_location", ringtone_list.userdef_location);
	hv_puti (rl, "userdef_count",    ringtone_list.userdef_count);
	XS_RETURNr (rl);
	}
    XSRETURN_UNDEF;
    /* GetRingtoneList */

void
GetSMSCenter (self, start, end)
    HvObject	*self;
    int		start;
    int		end;

  PPCODE:
    gn_sms_message_center	messagecenter;
    int				i;
    AV				*scl = newAV ();

    if (opt_v) warn ("GetSMSCenter (%d, %d)\n", start, end);

    if (start < 0 || start > 255) {
	set_errors ("messagecenter location should be in valid range 0..255");
	XSRETURN_UNDEF;
	}

    if (end <= 0 || end > 255) {
	end = 255;
	/* NYI - find last smscenter used
	gn_memory_status ms = {mt, 0, 0};
	data->memory_status = &ms;
	if (gn_sm_func (self, GN_OP_GetMemoryStatus)) {
	    end = ms.used + 1;
	    if (end < start)
		end = start;
	    }
	*/
	}

    for (i = start; i <= end; i++) {
	HV *mc = newHV ();

	clear_data ();
	Zero (&messagecenter, 1, messagecenter);
	messagecenter.id = i;
	data->message_center = &messagecenter;
	if (gn_sm_functions (GN_OP_GetSMSCenter, data, state) == GN_ERR_NONE) {
	    hv_puti (mc, "id", messagecenter.id);
	    hv_puts (mc, "name", messagecenter.name);
	    hv_puti (mc, "defaultname", messagecenter.default_name);
	    switch (messagecenter.format) {
		case GN_SMS_MF_Text:   hv_puts (mc, "format", "Text");      break;
		case GN_SMS_MF_Voice:  hv_puts (mc, "format", "VoiceMail"); break;
		case GN_SMS_MF_Fax:    hv_puts (mc, "format", "Fax");       break;
		case GN_SMS_MF_Email:
		case GN_SMS_MF_UCI:    hv_puts (mc, "format", "Email");     break;
		case GN_SMS_MF_ERMES:  hv_puts (mc, "format", "Fermes");    break;
		case GN_SMS_MF_X400:   hv_puts (mc, "format", "X.400");     break;
		case GN_SMS_MF_Paging: hv_puts (mc, "format", "Paging");    break;
		default:               hv_puts (mc, "format", "unknown");   break;
		}
	    switch (messagecenter.validity) {
		case GN_SMS_VP_1H:  hv_puts (mc, "validity", "1 hour");       break;
		case GN_SMS_VP_6H:  hv_puts (mc, "validity", "6 hours");      break;
		case GN_SMS_VP_24H: hv_puts (mc, "validity", "24 hours");     break;
		case GN_SMS_VP_72H: hv_puts (mc, "validity", "72 hours");     break;
		case GN_SMS_VP_1W:  hv_puts (mc, "validity", "1 Week");       break;
		case GN_SMS_VP_Max: hv_puts (mc, "validity", "Maximum Time"); break;
		default:            hv_puts (mc, "validity", "unknown");      break;
		}
	    hv_puti (mc, "type",            messagecenter.smsc.type);
	    hv_puts (mc, "smscnumber",      messagecenter.smsc.number);
	    hv_puti (mc, "recipienttype",   messagecenter.recipient.type);
	    hv_puts (mc, "recipientnumber", messagecenter.recipient.number);
	    av_addr (scl, mc);
	    }
	}
    XS_RETURNr (scl);
    /* GetSMSCenter */

void
GetAlarm (self)
    HvObject		*self;

  PPCODE:
    gn_calnote_alarm	alarm;

    if (opt_v) warn ("GetAlarm ()\n");

    clear_data ();
    data->alarm = &alarm;
    if (gn_sm_functions (GN_OP_GetAlarm, data, state) == GN_ERR_NONE) {
	char time[8];
	HV *ah = newHV ();
	sprintf (time, "%02d:%02d", alarm.timestamp.hour, alarm.timestamp.minute);
	hv_puts (ah, "alarm", time);
	hv_puts (ah, "state", (alarm.enabled ? "on" : "off"));
	XS_RETURNr (ah);
	}
    XSRETURN_UNDEF;
    /* GetAlarm */

void
GetRF (self)
    HvObject	*self;

  PPCODE:
    float	rflevel = -1;
    gn_rf_unit	rfunit  = GN_RF_Arbitrary;
    HV		*rf = newHV ();;

    if (opt_v) warn ("GetRF ()\n");

    clear_data ();
    data->rf_unit  = &rfunit;
    data->rf_level = &rflevel;
    if (gn_sm_func (self, GN_OP_GetRFLevel)) {
	hv_putn (rf, "level", rflevel);
	hv_puti (rf, "unit", rfunit);
	}
    XS_RETURNr (rf);
    /* GetRF */

void
GetPowerStatus (self)
    HvObject	*self;

  PPCODE:
    gn_power_source	powersource  = -1;
    float		batterylevel = -1;
    gn_battery_unit	batt_units   = GN_BU_Arbitrary;
    HV			*ps          = newHV ();

    if (opt_v) warn ("GetPowerStatus ()\n");

    clear_data ();
    data->battery_unit  = &batt_units;
    data->battery_level = &batterylevel;
    data->power_source  = &powersource;
    if (gn_sm_functions (GN_OP_GetBatteryLevel, data, state) == GN_ERR_NONE)
	hv_putn (ps, "level",  batterylevel);
    if (gn_sm_functions (GN_OP_GetPowersource,  data, state) == GN_ERR_NONE)
	hv_puts (ps, "source", gn_power_source2str (powersource));
    XS_RETURNr (ps);
    /* GetPowerStatus */

void
GetMemoryStatus (self)
    HvObject *self;

  PPCODE:
    HV *ms = newHV ();

    if (opt_v) warn ("GetMemoryStatus ()\n");

    clear_data ();
    data->memory_status = &SIMMemoryStatus;

    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "simused", SIMMemoryStatus.used);
	hv_puti (ms, "simfree", SIMMemoryStatus.free);
	}
    data->memory_status = &PhoneMemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "phoneused", PhoneMemoryStatus.used);
	hv_puti (ms, "phonefree", PhoneMemoryStatus.free);
	}
    data->memory_status = &DC_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "dcused", DC_MemoryStatus.used);
	hv_puti (ms, "dcfree", DC_MemoryStatus.free);
	}
    data->memory_status = &EN_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "enused", EN_MemoryStatus.used);
	hv_puti (ms, "enfree", EN_MemoryStatus.free);
	}
    data->memory_status = &FD_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "fdused", FD_MemoryStatus.used);
	hv_puti (ms, "fdfree", FD_MemoryStatus.free);
	}
    data->memory_status = &LD_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "ldused", LD_MemoryStatus.used);
	hv_puti (ms, "ldfree", LD_MemoryStatus.free);
	}
    data->memory_status = &MC_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "mcused", MC_MemoryStatus.used);
	hv_puti (ms, "mcfree", MC_MemoryStatus.free);
	}
    data->memory_status = &ON_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "onused", ON_MemoryStatus.used);
	hv_puti (ms, "onfree", ON_MemoryStatus.free);
	}
    data->memory_status = &RC_MemoryStatus;
    if (gn_sm_functions (GN_OP_GetMemoryStatus, data, state) == GN_ERR_NONE) {
	hv_puti (ms, "rcused", RC_MemoryStatus.used);
	hv_puti (ms, "rcfree", RC_MemoryStatus.free);
	}
    XS_RETURNr (ms);
    /* GetMemoryStatus */

void
GetSMSStatus (self)
    HvObject		*self;

  PPCODE:
    gn_sms_status	SMSStatus = {0, 0, 0, 0};

    if (opt_v) warn ("GetSMSStatus ()\n");

    clear_data ();
    data->sms_status = &SMSStatus;
    if (gn_sm_functions (GN_OP_GetSMSStatus, data, state) == GN_ERR_NONE) {
	HV *ss = newHV ();
	hv_puti (ss, "unread", SMSStatus.unread);
	hv_puti (ss, "read",   SMSStatus.number);
	XS_RETURNr (ss);
	}
    XSRETURN_UNDEF;
    /* GetSMSStatus */

void
GetNetworkInfo (self)
    HvObject		*self;

  PPCODE:
    gn_network_info	NetworkInfo;
    char		buffer[10];

    if (opt_v) warn ("GetNetworkInfo ()\n");

    clear_data ();
    data->network_info = &NetworkInfo;

    if (gn_sm_func (self, GN_OP_GetNetworkInfo)) {
	HV *ni = newHV ();
	hv_puts (ni, "name",        (char *)gn_network_name_get (NetworkInfo.network_code));
	hv_puts (ni, "countryname", (char *)gn_country_name_get (NetworkInfo.network_code));
	hv_puts (ni, "networkcode", NetworkInfo.network_code);
	Zero (buffer, 10, char);
	sprintf (buffer, "%02x%02x", NetworkInfo.cell_id[0], NetworkInfo.cell_id[1]);
	hv_puts (ni, "cellid",      buffer);
	Zero (buffer, 10, char);
	sprintf (buffer, "%02x%02x", NetworkInfo.LAC[0], NetworkInfo.LAC[1]);
	hv_puts (ni, "lac",         buffer);
	XS_RETURNr (ni);
	}
    XSRETURN_UNDEF;
    /* GetNetworkInfo */

void
GetWapBookmark (self, location)
    HvObject		*self;
    int			location;

  PPCODE:
    gn_wap_bookmark	wapbookmark;

    if (opt_v) warn ("GetWapBookmark (%d)\n", location);

    clear_data ();
    Zero (&wapbookmark, 1, wapbookmark);
    wapbookmark.location = location;
    data->wap_bookmark   = &wapbookmark;
    if (gn_sm_functions (GN_OP_GetWAPBookmark, data, state) == GN_ERR_NONE) {
	HV *wbm = newHV ();
	hv_puti (wbm, "location", location);
	hv_puts (wbm, "name",     wapbookmark.name);
	hv_puts (wbm, "url",      wapbookmark.URL);
	XS_RETURNr (wbm);
	}
    XSRETURN_UNDEF;
    /* GetWapBookmark */

void
GetWapSettings (self, location)
    HvObject		*self;
    int			location;

  PPCODE:
    gn_wap_setting	wapsetting;
    char		*key;
    HV			*ws;

    if (opt_v) warn ("GetWapSettings (%d)\n", location);

    clear_data ();
    Zero (&wapsetting, 1, wapsetting);
    wapsetting.location = location;
    data->wap_setting   = &wapsetting;
    unless (gn_sm_funct (self, GN_OP_GetWAPSetting))
	XSRETURN_UNDEF;

    ws = newHV ();
    hv_puti (ws, "location", location);
    hv_puts (ws, "name",     wapsetting.name);
    hv_puts (ws, "home",     wapsetting.home);

    key = "session";
    switch (wapsetting.session) {
	case GN_WAP_SESSION_TEMPORARY: hv_puts (ws, key, "temporary");   break;
	case GN_WAP_SESSION_PERMANENT: hv_puts (ws, key, "permanent");   break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}
    hv_puts (ws, "security", wapsetting.security ? "yes" : "no");

    key = "bearer";
    switch (wapsetting.bearer) {
	case GN_WAP_BEARER_GSMDATA:    hv_puts (ws, key, "GSM data");    break;
	case GN_WAP_BEARER_GPRS:       hv_puts (ws, key, "GPRS");        break;
	case GN_WAP_BEARER_SMS:        hv_puts (ws, key, "SMS");         break;
	case GN_WAP_BEARER_USSD:       hv_puts (ws, key, "USSD");        break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "gsm_data_auth";
    switch (wapsetting.gsm_data_authentication) {
	case GN_WAP_AUTH_NORMAL:       hv_puts (ws, key, "normal");      break;
	case GN_WAP_AUTH_SECURE:       hv_puts (ws, key, "secure");      break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "call_type";
    switch (wapsetting.call_type) {
	case GN_WAP_CALL_ANALOGUE:     hv_puts (ws, key, "analog");      break;
	case GN_WAP_CALL_ISDN:         hv_puts (ws, key, "IDSN");        break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "call_speed";
    switch (wapsetting.call_speed) {
	case GN_WAP_CALL_AUTOMATIC:    hv_puts (ws, key, "automatic");   break;
	case GN_WAP_CALL_9600:         hv_puts (ws, key, "9600");        break;
	case GN_WAP_CALL_14400:        hv_puts (ws, key, "14400");       break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "gsm_data_login";
    switch (wapsetting.gsm_data_login) {
	case GN_WAP_LOGIN_MANUAL:      hv_puts (ws, key, "manual");      break;
	case GN_WAP_LOGIN_AUTOLOG:     hv_puts (ws, key, "automatic");   break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    hv_puts (ws, "number",        wapsetting.number);
    hv_puts (ws, "gsm_data_ip",   wapsetting.gsm_data_ip);
    hv_puts (ws, "gsm_data_user", wapsetting.gsm_data_username);
    hv_puts (ws, "gsm_data_pass", wapsetting.gsm_data_password);

    key = "gprs_connection";
    switch (wapsetting.gprs_connection) {
	case GN_WAP_GPRS_WHENNEEDED:   hv_puts (ws, key, "when needed"); break;
	case GN_WAP_GPRS_ALWAYS:       hv_puts (ws, key, "always");      break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "gprs_auth";
    switch (wapsetting.gprs_authentication) {
	case GN_WAP_AUTH_NORMAL:       hv_puts (ws, key, "normal");      break;
	case GN_WAP_AUTH_SECURE:       hv_puts (ws, key, "secure");      break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    key = "gprs_login";
    switch (wapsetting.gprs_login) {
	case GN_WAP_LOGIN_MANUAL:      hv_puts (ws, key, "manual");      break;
	case GN_WAP_LOGIN_AUTOLOG:     hv_puts (ws, key, "automatic");   break;
	default:                       hv_puts (ws, key, "unknown");     break;
	}

    hv_puts (ws, "access_point",  wapsetting.access_point_name);
    hv_puts (ws, "gprs_ip",       wapsetting.gprs_ip);
    hv_puts (ws, "gprs_user",     wapsetting.gprs_username);
    hv_puts (ws, "gprs_pass",     wapsetting.gprs_password);
    hv_puts (ws, "sms_servicenr", wapsetting.sms_service_number);
    hv_puts (ws, "sms_servernr",  wapsetting.sms_server_number);
    XS_RETURNr (ws);
    /* GetWapSettings */

void
GetTodo (self, start, end)
    HvObject	*self;
    int		start;
    int		end;

  PPCODE:
    gn_todo_list	todolist;
    gn_todo		todo;
    int			i;
    AV			*tdl = newAV ();

    if (opt_v) warn ("GetTodo (%d, %d)\n", start, end);

    if (start < 0 || start > 255) {
	set_errors ("todo location should be in valid range 0..255");
	XSRETURN_UNDEF;
	}

    if (end <= 0 || end > 255) {
	end = 255;
	/* NYI - find last todo location used
	gn_memory_status ms = {mt, 0, 0};
	data->memory_status = &ms;
	if (gn_sm_func (self, GN_OP_GetMemoryStatus)) {
	    end = ms.used + 1;
	    if (end < start)
		end = start;
	    }
	*/
	}

    for (i = start; i < end; i++) {
	clear_data ();
	Zero (&todolist, 1, todolist);
	Zero (&todo,     1, gn_todo);
	todo.location   = i;
	data->todo      = &todo;
	data->todo_list = &todolist;
	if (gn_sm_func (self, GN_OP_GetToDo)) {
	    HV *t = newHV ();
	    hv_puti (t, "location", i);
	    hv_puts (t, "text",     todo.text);
	    switch (todo.priority) {
		case GN_TODO_LOW:    hv_puts (t, "priority", "low");     break;
		case GN_TODO_MEDIUM: hv_puts (t, "priority", "medium");  break;
		case GN_TODO_HIGH:   hv_puts (t, "priority", "high");    break;
		default:             hv_puts (t, "priority", "unknown"); break;
		}
	    av_addr (tdl, t);
	    }
	}
    XS_RETURNr (tdl);

void
GetProfiles (self, start, end)
    HvObject		*self;
    int			start;
    int			end;

  PPCODE:
    gn_profile		profile;
    gn_ringtone_list	rtl;
    char		model[64] = "";
    int			i, max_profiles = 7;
    char		*key;
    HV			*p;
    AV			*pl = newAV ();

    if (opt_v) warn ("GetProfiles (%d, %d)\n", start, end);

    warn ("GetProfile () @ %d\n", __LINE__);
    clear_data ();
    data->model = model;
    unless (gn_sm_funct (self, GN_OP_GetModel))
	XSRETURN_UNDEF;

    if (strcmp (model, "NSE-1") == 0)
	max_profiles = 3;

    warn ("GetProfile () @ %d (%s)\n", __LINE__, model);

    if (start < 0 || start > max_profiles) {
	set_errors ("profile location should be in valid range 1..7");
	XSRETURN_UNDEF;
	}

    if (end <= 0 || end > max_profiles) {
	end = max_profiles;
	/* NYI - find last profile used
	gn_memory_status ms = {mt, 0, 0};
	data->memory_status = &ms;
	if (gn_sm_func (self, GN_OP_GetMemoryStatus)) {
	    end = ms.used + 1;
	    if (end < start)
		end = start;
	    }
	*/
	}

    warn ("GetProfile () @ %d\n", __LINE__);
    Zero (&rtl,     1, rtl);
    Zero (&profile, 1, profile);
    profile.number      = 0;
    data->profile       = &profile;
    data->ringtone_list = &rtl;
    unless (gn_sm_funct (self, GN_OP_GetProfile)) /* use GN_OP_GetActiveProfile? */
	XSRETURN_UNDEF;

    warn ("GetProfile () @ %d\n", __LINE__);
    for (i = start; i < end; i++) {
	if (i) {
	    clear_data ();
	    Zero (&profile, 1, profile);
	    Zero (&rtl,     1, rtl);
	    data->profile       = &profile;
	    data->ringtone_list = &rtl;

	    profile.number = i;
	    unless (gn_sm_func (self, GN_OP_GetProfile))
		continue;
	    }

	warn ("GetProfile () @ %d\n", __LINE__);
	p = newHV ();
	hv_puti (p, "number",      i);
	hv_puts (p, "name",        profile.name);
	hv_puts (p, "defaultname", profile.default_name);

	key = "call_alert";
	switch (profile.call_alert) {
	    case GN_PROFILE_CALLALERT_Ringing:      hv_puts (p, key, "Ringing");       break;
	    case GN_PROFILE_CALLALERT_Ascending:    hv_puts (p, key, "Ascending");     break;
	    case GN_PROFILE_CALLALERT_RingOnce:     hv_puts (p, key, "Ring once");     break;
	    case GN_PROFILE_CALLALERT_BeepOnce:     hv_puts (p, key, "Beep once");     break;
	    case GN_PROFILE_CALLALERT_CallerGroups: hv_puts (p, key, "Caller groups"); break;
	    case GN_PROFILE_CALLALERT_Off:          hv_puts (p, key, "Off");           break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	hv_puti (p, "ringtonenumber", profile.ringtone);

	key = "volume_level";
	switch (profile.volume) {
	    case GN_PROFILE_VOLUME_Level1:          hv_puts (p, key, "Level 1");       break;
	    case GN_PROFILE_VOLUME_Level2:          hv_puts (p, key, "Level 2");       break;
	    case GN_PROFILE_VOLUME_Level3:          hv_puts (p, key, "Level 3");       break;
	    case GN_PROFILE_VOLUME_Level4:          hv_puts (p, key, "Level 4");       break;
	    case GN_PROFILE_VOLUME_Level5:          hv_puts (p, key, "Level 5");       break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	key = "message_tone";
	switch (profile.message_tone) {
	    case GN_PROFILE_MESSAGE_NoTone:         hv_puts (p, key, "No tone");       break;
	    case GN_PROFILE_MESSAGE_Standard:       hv_puts (p, key, "Standard");      break;
	    case GN_PROFILE_MESSAGE_Special:        hv_puts (p, key, "Special");       break;
	    case GN_PROFILE_MESSAGE_BeepOnce:       hv_puts (p, key, "Beep once");     break;
	    case GN_PROFILE_MESSAGE_Ascending:      hv_puts (p, key, "Ascending");     break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	key = "keypad_tone";
	switch (profile.keypad_tone) {
	    case GN_PROFILE_KEYVOL_Off:             hv_puts (p, key, "Off");           break;
	    case GN_PROFILE_KEYVOL_Level1:          hv_puts (p, key, "Level 1");       break;
	    case GN_PROFILE_KEYVOL_Level2:          hv_puts (p, key, "Level 2");       break;
	    case GN_PROFILE_KEYVOL_Level3:          hv_puts (p, key, "Level 3");       break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	key = "warning_tone";
	switch (profile.warning_tone) {
	    case GN_PROFILE_WARNING_Off:            hv_puts (p, key, "Off");           break;
	    case GN_PROFILE_WARNING_On:             hv_puts (p, key, "On");            break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	key = "vibration";
	switch (profile.vibration) {
	    case GN_PROFILE_VIBRATION_Off:          hv_puts (p, key, "Off");           break;
	    case GN_PROFILE_VIBRATION_On:           hv_puts (p, key, "On");            break;
	    default:                                hv_puts (p, key, "unknown");       break;
	    }

	hv_puti (p, "caller_groups",    profile.caller_groups);
	hv_puts (p, "automatic_answer", profile.automatic_answer ? "On" : "Off");
	av_addr (pl, p);
	}
    XS_RETURNr (pl);
    /* GetProfiles */

void
GetDirTree (self, memorytype)
    HvObject		*self;
    char		*memorytype;

  PPCODE:
    char		*mt;
    gn_file_list	fl;
    HV			*dt;
    int			i;

    if (opt_v) warn ("GetDirTree (%s)\n", memorytype);

         if (!strcmp (memorytype, "ME"))
	mt = "A:";
    else if (!strcmp (memorytype, "SM"))
	mt = "B:";
    else {
	set_errors ("usage: GetDirTree ('ME' | 'SM')");
	XSRETURN_UNDEF;
	}

    clear_data ();
    Zero (&fl, 1, fl);
    sprintf (fl.path, "%s\\*", mt);
    data->file_list = &fl;
    unless (gn_sm_func (self, GN_OP_GetFileList))
	XSRETURN_UNDEF;

    dt = newHV ();
    hv_puts (dt, "memorytype",	memorytype);
    hv_puts (dt, "path",	mt);
    hv_puti (dt, "file_count",	fl.file_count);
    hv_puti (dt, "dir_size",	fl.size);

    hv_putr (dt, "tree",	walk_tree (self, mt, &fl));

    XS_RETURNr (dt);
    /* GetDirTree */

void
SendSMS (self, smshash)
    HvObject	*self;
    HV		*smshash;

  PPCODE:
    gn_sms	sms;
    SV		**value;
    char	*str;
    STRLEN	l;
    int		err = GN_ERR_NONE;

    if (opt_v) warn ("SendSMS ({ destination => ..., message => ... })\n");
    /* Options in gnokii:
     * smsc
     * smscno
     * long
     * report
     * validity
     * class
     * 8bit
     * imelody
     * animation
     * concat
     * wappush
     */

    clear_data ();
    gn_sms_default_submit (&sms);

    if ((value = hv_fetch (smshash, "report", 6, 0)) && SvTRUE (*value))
	sms.delivery_report = true;
    else
	sms.delivery_report = false;
    sms.type = GN_SMS_MT_Submit;

    unless ((value = hv_fetch (smshash, "destination", 11, 0))) {
	set_errors ("destination is a required attribute in SendSMS ()");
	XSRETURN_UNDEF;
	}

    str = SvPV (*value, l);
    if (l >= sizeof (sms.remote.number)) {
	set_errors ("Destination is too long");
	XSRETURN_UNDEF;
	}
    strcpy (sms.remote.number, str);
    sms.remote.type = get_number_type (str);
    if (sms.remote.type == GN_GSM_NUMBER_Alphanumeric) {
	set_errors ("Invalid phone number");
	XSRETURN_UNDEF;
	}
#ifdef DEBUG_MODULE
    warn ("SendSMS: destination set to '%s'\n", str);
#endif

    if ((value = hv_fetch (smshash, "message", 7, 0)) ||
        (value = hv_fetch (smshash, "text",    4, 0))) {
	char		*text = SvPV (*value, l);
	unsigned int	i = 0;
#ifdef DEBUG_MODULE
	warn ("SendSMS: got text: '%s' (%d)\n", text, l);
#endif

	if (l > GN_SMS_MAX_LENGTH) {
	    set_errors ("No support (yet) for long messages");
	    XSRETURN_UNDEF;
	    }

	sms.udh.length = 0;
	sms.user_data[0].type = GN_SMS_DATA_Text;
	strncpy (sms.user_data[0].u.text, text, GN_SMS_MAX_LENGTH + 1);
	sms.user_data[0].u.text[GN_SMS_MAX_LENGTH] = '\0';

	while (sms.user_data[i].type != GN_SMS_DATA_None) {
	    if ((sms.user_data[i].type == GN_SMS_DATA_Text      ||
		 sms.user_data[i].type == GN_SMS_DATA_NokiaText ||
		 sms.user_data[i].type == GN_SMS_DATA_iMelody) &&
		 !gn_char_def_alphabet (sms.user_data[i].u.text))
		sms.dcs.u.general.alphabet = GN_SMS_DCS_UCS2;
	    i++;
	    }
	}
    else {
	set_errors ("text is a required attribute in SendSMS ()");
	XSRETURN_UNDEF;
	}

    if ((value = hv_fetch (smshash, "smscnumber", 10, 0))) {
#ifdef DEBUG_MODULE
	warn ("SendSMS: got smsc number: '%s'\n", SvPV_nolen (*value));
#endif
	strncpy (sms.smsc.number, SvPV_nolen (*value), sizeof (sms.smsc.number) - 1);
	if (sms.smsc.number[0] == '+')
	    sms.smsc.type = GN_GSM_NUMBER_International;
	else
	    sms.smsc.type = GN_GSM_NUMBER_Unknown;
	}
    else
    if ((value = hv_fetch (smshash, "smscindex", 9, 0))) {
	gn_sms_message_center messagecenter;
#ifdef DEBUG_MODULE
	warn ("SendSMS: got smsc index: %i\n", SvIV (*value));
#endif

	Zero (&messagecenter, 1, messagecenter);
	messagecenter.id = SvIV (*value);
	data->message_center = &messagecenter;
#ifdef DEBUG_MODULE
	warn ("SendSMS @ %d: message center number = %d\n", __LINE__, data->message_center->id);
#endif
	if (data->message_center->id < 1 || data->message_center->id > 5) {
	    set_errors ("Messagecenter index must be between 1 and 5");
	    XSRETURN_UNDEF;
	    }

	if (gn_sm_functions (GN_OP_GetSMSCenter, data, state) == GN_ERR_NONE) {
	    snprintf (sms.smsc.number, sizeof (sms.smsc.number), "%s", data->message_center->smsc.number);
	    sms.smsc.type = data->message_center->smsc.type;
	    }
#ifdef DEBUG_MODULE
	warn ("SendSMS @ %d: smsc number = %s\n", __LINE__, sms.smsc.number);
#endif
	}

    unless (sms.smsc.number[0]) {
#ifdef DEBUG_MODULE
	warn ("SendSMS @ %d: set default smsc\n", __LINE__);
#endif
	data->message_center = calloc (1, sizeof (gn_sms_message_center));
	data->message_center->id = 1;
	if (gn_sm_functions (GN_OP_GetSMSCenter, data, state) == GN_ERR_NONE) {
	    snprintf (sms.smsc.number, sizeof (sms.smsc.number), "%s", data->message_center->smsc.number);
	    sms.smsc.type = data->message_center->smsc.type;
	    }
	free (data->message_center);
	}
#ifdef DEBUG_MODULE
    warn ("SendSMS @ %d: set validity\n", __LINE__);
#endif

    if ((value = hv_fetch (smshash, "validity", 8, 0)))
	sms.validity = SvIV (*value);
#ifdef DEBUG_MODULE
    warn ("SendSMS @ %d: msg: '%s'\n", __LINE__, sms.user_data[0].u.text);
#endif
    data->sms = &sms;
#ifdef DEBUG_MODULE
    warn ("SendSMS @ %d before send\n", __LINE__);
#endif
    if (err == GN_ERR_NONE)
	err = gn_sms_send (data, state);
    set_errori (err);
#ifdef DEBUG_MODULE
    warn ("SendSMS @ %d after send\n", __LINE__);
#endif
    ST (0) = sv_2mortal (newSViv (err));
    XSRETURN (1);

int
WritePhonebookEntry (self, entryhash)
HvObject *self;
HV *entryhash;
PREINIT:
gn_error error;
gn_phonebook_entry *entry;
char *mem_type;
CODE:
{
        Newxz (entry, 1, gn_phonebook_entry);
        entry->location = SvIV (*hv_fetch (entryhash, "location", 8, 0));
	strcpy (entry->number, SvPV_nolen (*hv_fetch (entryhash, "number", 6, 0)));
	entry->caller_group = SvIV (*hv_fetch (entryhash, "callergroup", 11, 0));
	strcpy (entry->name, SvPV_nolen (*hv_fetch (entryhash, "name", 4, 0)));
	mem_type = SvPV_nolen (*hv_fetch (entryhash, "memorytype", 10, 0));
	/* borrowed from gnokii.c */
	if (!strncmp (mem_type, "ME", 2))
	  entry->memory_type = GN_MT_ME;
	else
	{
	  if (!strncmp (mem_type, "SM", 2))
	    entry->memory_type = GN_MT_SM;
	}
	/* here we will add a part for subentries if this really is needed */
	data->phonebook_entry = entry;
	RETVAL = gn_sm_functions (GN_OP_WritePhonebook, data, state);
#ifdef DEBUG_MODULE
	warn ("Vor Free");
#endif
	Safefree (entry);
}
OUTPUT:
        RETVAL

int
SetDateTime (self, timestamp)
HvObject *self;
time_t timestamp;
PREINIT:
gn_timestamp *date;
CODE:
{
        Newxz (date, 1, gn_timestamp);
	clear_data ();
	HASH_TO_GSMDT (date, &timestamp);
	data->datetime = date;
	RETVAL = gn_sm_functions (GN_OP_SetDateTime, data, state);
}
OUTPUT:
        RETVAL

int
WriteWapBookmark (self, waphash)
HvObject *self;
HV *waphash;
PREINIT:
gn_wap_bookmark *wapbookmark;
CODE:
{
        clear_data ();
	Newxz (wapbookmark, 1, gn_wap_bookmark);
	strcpy (wapbookmark->name, SvPV_nolen (*hv_fetch (waphash, "name", 4, 0)));
	strcpy (wapbookmark->URL, SvPV_nolen (*hv_fetch (waphash, "url", 3, 0)));
	data->wap_bookmark = wapbookmark;
	RETVAL = gn_sm_functions (GN_OP_WriteWAPBookmark, data, state);
#ifdef DEBUG_MODULE
	warn ("Loc:%d\n",wapbookmark->location);
#endif
	if (RETVAL == GN_ERR_NONE)
	  hv_store (waphash, "number", 6, sv_2mortal (newSViv (wapbookmark->location)), 0);
	Safefree (wapbookmark);
	data->wap_bookmark = NULL;
}
OUTPUT:
        RETVAL

int
DeleteWapBookmark (self, location)
HvObject *self;
int location;
PREINIT:
gn_wap_bookmark *wapbookmark;
CODE:
{
        clear_data ();
	Newxz (wapbookmark, 1, gn_wap_bookmark);
	wapbookmark->location = location;
	data->wap_bookmark = wapbookmark;
	RETVAL = gn_sm_functions (GN_OP_DeleteWAPBookmark, data, state);
	Safefree (wapbookmark);
	data->wap_bookmark = NULL;
}
OUTPUT:
        RETVAL

int
WriteWapSetting (self, location, wapsethash)
HvObject *self;
int location;
HV *wapsethash;
PREINIT:
char *buf;
gn_wap_setting *wapsetting;
CODE:
{
        clear_data ();
	Newxz (wapsetting, 1, gn_wap_setting);
	wapsetting->location = location;
	strcpy (wapsetting->number, SvPV_nolen (*hv_fetch (wapsethash, "number", 6, 0)));
	strcpy (wapsetting->home, SvPV_nolen (*hv_fetch (wapsethash, "home", 4, 0)));
	strcpy (wapsetting->gsm_data_ip, SvPV_nolen (*hv_fetch (wapsethash,"gsm_data_ip", 11, 0)));
	strcpy (wapsetting->gprs_ip, SvPV_nolen (*hv_fetch (wapsethash, "ip", 2, 0)));
	strcpy (wapsetting->name, SvPV_nolen (*hv_fetch (wapsethash, "name", 4, 0)));
	strcpy (wapsetting->gsm_data_username, SvPV_nolen (*hv_fetch (wapsethash, "gsm_data_username", 17, 0)));
	strcpy (wapsetting->gsm_data_password, SvPV_nolen (*hv_fetch (wapsethash, "gsm_data_password", 17, 0)));
	strcpy (wapsetting->gprs_username, SvPV_nolen (*hv_fetch (wapsethash, "username", 8, 0)));
	strcpy (wapsetting->gprs_password, SvPV_nolen (*hv_fetch (wapsethash, "password", 8, 0)));
	strcpy (wapsetting->access_point_name, SvPV_nolen (*hv_fetch (wapsethash, "apn", 3, 0)));
	strcpy (wapsetting->sms_service_number, SvPV_nolen (*hv_fetch (wapsethash, "smsservicenumber", 16, 0)));
	strcpy (wapsetting->sms_server_number, SvPV_nolen (*hv_fetch (wapsethash, "smsservernumber", 15, 0)));
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "session", 7, 0)), "temporary"))
	  wapsetting->session = GN_WAP_SESSION_PERMANENT;
	else
	  wapsetting->session = GN_WAP_SESSION_TEMPORARY;
	if (hv_fetch (wapsethash, "security", 8, 0))
	  wapsetting->security = true;
	else
	  wapsetting->security = false;
	buf = SvPV_nolen (*hv_fetch (wapsethash, "bearer", 6, 0));
	if (!strcasecmp (buf, "gsm data"))
	  wapsetting->bearer = GN_WAP_BEARER_GSMDATA;
	else if (!strcasecmp (buf, "gprs"))
	  wapsetting->bearer = GN_WAP_BEARER_GPRS;
	else if (!strcasecmp (buf, "sms"))
	  wapsetting->bearer = GN_WAP_BEARER_SMS;
	else
	  wapsetting->bearer = GN_WAP_BEARER_USSD;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "gsm_data_authentication", 23, 0)), "normal"))
	  wapsetting->gsm_data_authentication = GN_WAP_AUTH_SECURE;
	else
	  wapsetting->gsm_data_authentication = GN_WAP_AUTH_NORMAL;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "gprs_authentication", 19, 0)), "normal"))
	  wapsetting->gprs_authentication = GN_WAP_AUTH_SECURE;
	else
	  wapsetting->gprs_authentication = GN_WAP_AUTH_NORMAL;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "call_type", 9, 0)), "ISDN"))
	  wapsetting->call_type = GN_WAP_CALL_ANALOGUE;
	else
	  wapsetting->call_type = GN_WAP_CALL_ISDN;
	buf = SvPV_nolen (*hv_fetch (wapsethash, "call_speed", 10, 0));
	if (!strcasecmp (buf, "automatic"))
	  wapsetting->call_speed = GN_WAP_CALL_AUTOMATIC;
	else if (!strcasecmp (buf, "9600"))
	  wapsetting->call_speed = GN_WAP_CALL_9600;
	else
	  wapsetting->call_speed = GN_WAP_CALL_14400;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "gsm_data_login", 14, 0)),"manual"))
	  wapsetting->gsm_data_login = GN_WAP_LOGIN_AUTOLOG;
	else
	  wapsetting->gsm_data_login = GN_WAP_LOGIN_MANUAL;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "gprs_login", 10, 0)), "manual"))
	  wapsetting->gprs_login = GN_WAP_LOGIN_AUTOLOG;
	else
	  wapsetting->gprs_login = GN_WAP_LOGIN_MANUAL;
	if (strcasecmp (SvPV_nolen (*hv_fetch (wapsethash, "gprs_connection", 14, 0)), "always"))
	  wapsetting->gprs_connection = GN_WAP_GPRS_WHENNEEDED;
	else
	  wapsetting->gprs_connection = GN_WAP_GPRS_ALWAYS;
	data->wap_setting = wapsetting;
	RETVAL = gn_sm_functions (GN_OP_WriteWAPSetting, data, state);
	Safefree (wapsetting);
	data->wap_setting = NULL;
}
OUTPUT:
        RETVAL

int
ActivateWapSetting (self, location)
HvObject *self;
int location;
PREINIT:
gn_wap_setting *wapsetting;
CODE:
{
        clear_data ();
	Newxz (wapsetting, 1, gn_wap_setting);
	wapsetting->location = location;
	data->wap_setting = wapsetting;
	RETVAL = gn_sm_functions (GN_OP_ActivateWAPSetting, data, state);
	Safefree (wapsetting);
	data->wap_setting = NULL;
}
OUTPUT:
        RETVAL

int
SetSpeedDial (self, number, location, mem_type)
HvObject *self;
int number;
int location;
char *mem_type;
PREINIT:
gn_speed_dial *entry;
CODE:
{
        clear_data ();
	Newxz (entry, 1, gn_speed_dial);
	if (!strcmp (mem_type, "ME"))
	  entry->memory_type = GN_MT_ME;
	else
	  entry->memory_type = GN_MT_SM;
	entry->number = number;
	entry->location = location;
	data->speed_dial = entry;
	RETVAL = gn_sm_functions (GN_OP_SetSpeedDial, data, state);
	Safefree (entry);
	data->speed_dial = NULL;
}
OUTPUT:
        RETVAL

int
CreateSMSFolder (self, name)
HvObject *self;
char *name;
PREINIT:
gn_sms_folder *folder;
CODE:
{
        clear_data ();
	Newxz (folder, 1, gn_sms_folder);
	strcpy (folder->name, name);
	data->sms_folder = folder;
	RETVAL = gn_sm_functions (GN_OP_CreateSMSFolder, data, state);
	Safefree (folder);
	data->sms_folder = NULL;
}
OUTPUT:
        RETVAL

void
SetAlarm (self, hour, minute)
    HvObject		*self;
    int			hour;
    int			minute;

  PPCODE:
    gn_calnote_alarm	at;
    int			err;

    clear_data ();
    if (hour   < 0 || hour   > 23) {
	set_errors ("Alarm hour must be in [0..23]");
	XSRETURN_UNDEF;
	}
    if (minute < 0 || minute > 59) {
	set_errors ("Alarm minute must be in [0..59]");
	XSRETURN_UNDEF;
	}

    Zero (&at, 1, gn_calnote_alarm);
    at.timestamp.hour   = hour;
    at.timestamp.minute = minute;
    at.timestamp.second = 0;
    at.enabled          = true;
    data->alarm         = &at;
    err = gn_sm_functions (GN_OP_SetAlarm, data, state);
    set_errori (err);
    XS_RETURNi (err);

void
WriteTodo (self, todohash)
    HvObject	*self;
    HV		*todohash;

  PPCODE:
    gn_todo	todo;
    char	*buf;
    int		err;

    clear_data ();
    Zero (&todo, 1, todo);
    strcpy (todo.text, SvPV_nolen (*hv_fetch (todohash, "text", 4, 0)));
    buf = SvPV_nolen (*hv_fetch (todohash, "priority", 8, 0));
    if      (!strcasecmp (buf, "low"))
	todo.priority = GN_TODO_LOW;
    else if (!strcasecmp (buf, "medium"))
	todo.priority = GN_TODO_MEDIUM;
    else if (!strcasecmp (buf, "high"))
	todo.priority = GN_TODO_HIGH;
    data->todo = &todo;
    err = gn_sm_functions (GN_OP_WriteToDo, data, state);
    set_errori (err);
    XS_RETURNi (todo.location);

void
DeleteAllTodos (self)
    HvObject	*self;

  PPCODE:
    int err;

    clear_data ();
    err = gn_sm_functions (GN_OP_DeleteAllToDos, data, state);
    set_errori (err);
    XSRETURNi (err);

void
WriteCalendarNote (self, location, calhash)
    HvObject		*self;
    int			location;
    HV			*calhash;

  PPCODE:
    gn_calnote		calnote;
    char		*buf;
    time_t		t, *t2;
    gn_timestamp	*timestamp;
    int			err;
    SV			**value;

    clear_data ();
    Zero (&calnote, 1, calnote);
    calnote.location = location;

    if ((value = hv_fetch (calhash, "date", 4, 0)) == NULL) {
	set_errors ("date is a required attribute for WriteCalendarNote ()");
	XSRETURN_UNDEF;
	}
    t = (time_t)SvIV (*value);
    t2 = &t;
    timestamp = &(calnote.time);
    HASH_TO_GSMDT (timestamp, t2);

    if ((value = hv_fetch (calhash, "text", 4, 0)) == NULL) {
	set_errors ("text is a required attribute for WriteCalendarNote ()");
	XSRETURN_UNDEF;
	}
    strcpy (calnote.text, SvPV_nolen (*value));

    if ((value = hv_fetch (calhash, "type", 4, 0)) == NULL)
	buf = "MEMO";
    else
	buf = SvPV_nolen (*value);

         if (!strncasecmp (buf, "misc", 4) || !strncasecmp (buf, "remi", 4))
	calnote.type  = GN_CALNOTE_REMINDER;
    else if (!strncasecmp (buf, "call", 4))
	calnote.type  = GN_CALNOTE_CALL;
    else if (!strncasecmp (buf, "meet", 4))
	calnote.type  = GN_CALNOTE_MEETING;
    else if (!strncasecmp (buf, "birt", 4))
	calnote.type  = GN_CALNOTE_BIRTHDAY;
    else if (!strncasecmp (buf, "memo", 4))
	calnote.type  = GN_CALNOTE_MEMO;

    value = hv_fetch (calhash, "number", 6, 0);
    if (calnote.type == GN_CALNOTE_CALL && !value) {
	set_errors ("number is a required attribute for WriteCalendarNote (CALL)");
	XSRETURN_UNDEF;
	}
    if (value)
	strcpy (calnote.phone_number, SvPV_nolen (*value));

    if ((value = hv_fetch (calhash, "alarm", 5, 0))) {
	t = (time_t)SvIV (*value);
	t2 = &t;
	calnote.alarm.enabled = true;
	timestamp = &(calnote.alarm.timestamp);
	HASH_TO_GSMDT (timestamp, t2);
	}


    if ((value = hv_fetch (calhash, "recurrence", 10, 0)) == NULL)
	buf = "NEVER";
    else
	buf = SvPV_nolen (*value);

	 if (!strncasecmp (buf, "neve", 4))
	calnote.recurrence = GN_CALNOTE_NEVER;
    else if (!strncasecmp (buf, "dail", 4))
	calnote.recurrence = GN_CALNOTE_DAILY;
    else if (!strncasecmp (buf, "week", 4))
	calnote.recurrence = GN_CALNOTE_WEEKLY;
    else if (!strncasecmp (buf, "2wee", 4))
	calnote.recurrence = GN_CALNOTE_2WEEKLY;
    else if (!strncasecmp (buf, "year", 4))
	calnote.recurrence = GN_CALNOTE_YEARLY;

    data->calnote = &calnote;
    err = gn_sm_functions (GN_OP_WriteCalendarNote, data, state);
    set_errori (err);
    XS_RETURNi (calnote.location);

void
PrintError (self, errno)
    HvObject	*self;

  CODE:
    if (opt_v) warn ("PrintError (%d)\n", errno);

    warn ("%s\n", gn_error_print (errno));

void
disconnect (self)
    HvObject	*self;

  PPCODE:
    if (opt_v) warn ("disconnect ()\n");

    if (hv_exists (self, "connection", 10)) {
	hv_delete (self, "connection", 10, 0);
	busterminate ();
	}

    XSRETURN (0);

double
constant (sv, arg)
  PREINIT:
    STRLEN	len;

  INPUT:
    SV		*sv
    char	*s = SvPV (sv, len);
    int		arg

  CODE:
    RETVAL = constant (s, len, arg);

  OUTPUT:
    RETVAL
