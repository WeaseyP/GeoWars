/* ------------------------------------------------------------
name: "warp_shot"
Code generated with Faust 2.79.3 (https://faust.grame.fr)
Compilation options: -lang c -ct 1 -cn WarpShot -es 1 -mcd 16 -mdd 1024 -mdy 33 -single -ftz 0
------------------------------------------------------------ */

#ifndef  __WarpShot_H__
#define  __WarpShot_H__

#ifndef FAUSTFLOAT
#define FAUSTFLOAT float
#endif 


#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define RESTRICT __restrict
#else
#define RESTRICT __restrict__
#endif

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct {
	int iVec0[2];
	int iRec0[2];
} WarpShotSIG0;

static WarpShotSIG0* newWarpShotSIG0() { return (WarpShotSIG0*)calloc(1, sizeof(WarpShotSIG0)); }
static void deleteWarpShotSIG0(WarpShotSIG0* dsp) { free(dsp); }

int getNumInputsWarpShotSIG0(WarpShotSIG0* RESTRICT dsp) {
	return 0;
}
int getNumOutputsWarpShotSIG0(WarpShotSIG0* RESTRICT dsp) {
	return 1;
}

static void instanceInitWarpShotSIG0(WarpShotSIG0* dsp, int sample_rate) {
	/* C99 loop */
	{
		int l0;
		for (l0 = 0; l0 < 2; l0 = l0 + 1) {
			dsp->iVec0[l0] = 0;
		}
	}
	/* C99 loop */
	{
		int l1;
		for (l1 = 0; l1 < 2; l1 = l1 + 1) {
			dsp->iRec0[l1] = 0;
		}
	}
}

static void fillWarpShotSIG0(WarpShotSIG0* dsp, int count, float* table) {
	/* C99 loop */
	{
		int i1;
		for (i1 = 0; i1 < count; i1 = i1 + 1) {
			dsp->iVec0[0] = 1;
			dsp->iRec0[0] = (dsp->iVec0[1] + dsp->iRec0[1]) % 65536;
			table[i1] = sinf(9.58738e-05f * (float)(dsp->iRec0[0]));
			dsp->iVec0[1] = dsp->iVec0[0];
			dsp->iRec0[1] = dsp->iRec0[0];
		}
	}
}

static float ftbl0WarpShotSIG0[65536];

#ifndef FAUSTCLASS 
#define FAUSTCLASS WarpShot
#endif

#ifdef __APPLE__ 
#define exp10f __exp10f
#define exp10 __exp10
#endif

typedef struct {
	int iVec1[2];
	int fSampleRate;
	float fConst0;
	float fRec1[2];
} WarpShot;

WarpShot* newWarpShot() { 
	WarpShot* dsp = (WarpShot*)calloc(1, sizeof(WarpShot));
	return dsp;
}

void deleteWarpShot(WarpShot* dsp) { 
	free(dsp);
}

void metadataWarpShot(MetaGlue* m) { 
	m->declare(m->metaInterface, "basics.lib/name", "Faust Basic Element Library");
	m->declare(m->metaInterface, "basics.lib/version", "1.21.0");
	m->declare(m->metaInterface, "compile_options", "-lang c -ct 1 -cn WarpShot -es 1 -mcd 16 -mdd 1024 -mdy 33 -single -ftz 0");
	m->declare(m->metaInterface, "filename", "warp_shot.dsp");
	m->declare(m->metaInterface, "maths.lib/author", "GRAME");
	m->declare(m->metaInterface, "maths.lib/copyright", "GRAME");
	m->declare(m->metaInterface, "maths.lib/license", "LGPL with exception");
	m->declare(m->metaInterface, "maths.lib/name", "Faust Math Library");
	m->declare(m->metaInterface, "maths.lib/version", "2.8.1");
	m->declare(m->metaInterface, "name", "warp_shot");
	m->declare(m->metaInterface, "oscillators.lib/name", "Faust Oscillator Library");
	m->declare(m->metaInterface, "oscillators.lib/version", "1.6.0");
	m->declare(m->metaInterface, "platform.lib/name", "Generic Platform Library");
	m->declare(m->metaInterface, "platform.lib/version", "1.3.0");
}

int getSampleRateWarpShot(WarpShot* RESTRICT dsp) {
	return dsp->fSampleRate;
}

int getNumInputsWarpShot(WarpShot* RESTRICT dsp) {
	return 0;
}
int getNumOutputsWarpShot(WarpShot* RESTRICT dsp) {
	return 1;
}

void classInitWarpShot(int sample_rate) {
	WarpShotSIG0* sig0 = newWarpShotSIG0();
	instanceInitWarpShotSIG0(sig0, sample_rate);
	fillWarpShotSIG0(sig0, 65536, ftbl0WarpShotSIG0);
	deleteWarpShotSIG0(sig0);
}

void instanceResetUserInterfaceWarpShot(WarpShot* dsp) {
}

void instanceClearWarpShot(WarpShot* dsp) {
	/* C99 loop */
	{
		int l2;
		for (l2 = 0; l2 < 2; l2 = l2 + 1) {
			dsp->iVec1[l2] = 0;
		}
	}
	/* C99 loop */
	{
		int l3;
		for (l3 = 0; l3 < 2; l3 = l3 + 1) {
			dsp->fRec1[l3] = 0.0f;
		}
	}
}

void instanceConstantsWarpShot(WarpShot* dsp, int sample_rate) {
	dsp->fSampleRate = sample_rate;
	dsp->fConst0 = 4.4e+02f / fminf(1.92e+05f, fmaxf(1.0f, (float)(dsp->fSampleRate)));
}
	
void instanceInitWarpShot(WarpShot* dsp, int sample_rate) {
	instanceConstantsWarpShot(dsp, sample_rate);
	instanceResetUserInterfaceWarpShot(dsp);
	instanceClearWarpShot(dsp);
}

void initWarpShot(WarpShot* dsp, int sample_rate) {
	classInitWarpShot(sample_rate);
	instanceInitWarpShot(dsp, sample_rate);
}

void buildUserInterfaceWarpShot(WarpShot* dsp, UIGlue* ui_interface) {
	ui_interface->openVerticalBox(ui_interface->uiInterface, "warp_shot");
	ui_interface->closeBox(ui_interface->uiInterface);
}

void computeWarpShot(WarpShot* dsp, int count, FAUSTFLOAT** RESTRICT inputs, FAUSTFLOAT** RESTRICT outputs) {
	FAUSTFLOAT* output0 = outputs[0];
	/* C99 loop */
	{
		int i0;
		for (i0 = 0; i0 < count; i0 = i0 + 1) {
			dsp->iVec1[0] = 1;
			float fTemp0 = ((1 - dsp->iVec1[1]) ? 0.0f : dsp->fConst0 + dsp->fRec1[1]);
			dsp->fRec1[0] = fTemp0 - floorf(fTemp0);
			output0[i0] = (FAUSTFLOAT)(0.1f * ftbl0WarpShotSIG0[max(0, min((int)(65536.0f * dsp->fRec1[0]), 65535))]);
			dsp->iVec1[1] = dsp->iVec1[0];
			dsp->fRec1[1] = dsp->fRec1[0];
		}
	}
}

#ifdef __cplusplus
}
#endif

#endif
