#include "pair-browse.h"

#include <jni.h>

static JavaVM *argus_android_vm = NULL;
static jclass argus_android_pair_cls = NULL;
static jobject argus_android_pair_context = NULL;
static char *argus_android_phone_label_text = NULL;

JNIEXPORT void JNICALL
Java_org_roojs_argus_PairBrowse_nativeBind (JNIEnv *env,
                                            jclass cls,
                                            jobject context)
{
	if ((*env)->GetJavaVM (env, &argus_android_vm) != JNI_OK) {
		g_message ("android pair: GetJavaVM failed");
		return;
	}
	if (argus_android_pair_cls != NULL) {
		(*env)->DeleteGlobalRef (env, argus_android_pair_cls);
	}
	argus_android_pair_cls = (*env)->NewGlobalRef (env, cls);
	if (argus_android_pair_context != NULL) {
		(*env)->DeleteGlobalRef (env, argus_android_pair_context);
	}
	argus_android_pair_context = (*env)->NewGlobalRef (env, context);
	g_message ("android pair: bound");
}

JNIEXPORT void JNICALL
Java_org_roojs_argus_PairBrowse_nativePhoneLabel (JNIEnv *env,
                                                  jclass cls,
                                                  jstring label)
{
	const char *utf;

	(void) cls;
	utf = (*env)->GetStringUTFChars (env, label, NULL);
	g_free (argus_android_phone_label_text);
	argus_android_phone_label_text = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, label, utf);
	}
}

const char *
argus_android_phone_label (void)
{
	if (argus_android_phone_label_text == NULL) {
		return "";
	}
	return argus_android_phone_label_text;
}

static JNIEnv *
argus_android_jni_env (void)
{
	JNIEnv *env = NULL;

	if (argus_android_vm == NULL) {
		g_message ("android pair: JavaVM not bound");
		return NULL;
	}
	if ((*argus_android_vm)->GetEnv (argus_android_vm, (void **) &env,
		JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if ((*argus_android_vm)->AttachCurrentThread (argus_android_vm, &env,
		NULL) != JNI_OK) {
		g_message ("android pair: attach failed");
		return NULL;
	}
	return env;
}

static gboolean
argus_android_pair_ready (JNIEnv **env_out)
{
	JNIEnv *env;

	*env_out = NULL;
	env = argus_android_jni_env ();
	if (env == NULL || argus_android_pair_cls == NULL
		|| argus_android_pair_context == NULL) {
		g_message ("android pair: browse not bound");
		return FALSE;
	}
	*env_out = env;
	return TRUE;
}

void
argus_android_pair_browse_start (void)
{
	JNIEnv *env = NULL;
	jmethodID mid;

	if (!argus_android_pair_ready (&env)) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, argus_android_pair_cls, "start",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, argus_android_pair_cls, mid,
			argus_android_pair_context);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}

char *
argus_android_pair_browse_poll (void)
{
	JNIEnv *env;
	jmethodID mid;
	jstring value;
	const char *utf;
	char *copy;

	env = argus_android_jni_env ();
	if (env == NULL || argus_android_pair_cls == NULL) {
		return g_strdup ("");
	}
	mid = (*env)->GetStaticMethodID (env, argus_android_pair_cls, "poll",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	value = (*env)->CallStaticObjectMethod (env, argus_android_pair_cls, mid);
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
	utf = (*env)->GetStringUTFChars (env, value, NULL);
	copy = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, value, utf);
	}
	(*env)->DeleteLocalRef (env, value);
	return copy;
}

void
argus_android_pair_browse_stop (void)
{
	JNIEnv *env = NULL;
	jmethodID mid;

	if (!argus_android_pair_ready (&env)) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, argus_android_pair_cls, "stop",
		"(Landroid/content/Context;)V");
	if (mid != NULL && !(*env)->ExceptionCheck (env)) {
		(*env)->CallStaticVoidMethod (env, argus_android_pair_cls, mid,
			argus_android_pair_context);
	}
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}
