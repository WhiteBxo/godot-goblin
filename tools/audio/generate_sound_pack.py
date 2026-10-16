"""Original Goblin SFX v1. Run from any cwd; Python 3.12 + requirements.txt.

No recordings, downloads, pretrained voices or external sample libraries.
All randomness is local and seeded. Generated WAVs are the distributable masters.
"""
from pathlib import Path
import hashlib
import json
import re
import wave

import numpy as np
from scipy.signal import butter, sosfilt, sosfiltfilt, resample_poly

ROOT = Path(__file__).resolve().parents[2]
RATE = 44100
RNG = np.random.default_rng(47001)


def clock(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def noise(t, low=100, high=3500):
    return sosfilt(butter(2, [low, high], btype="bandpass", fs=RATE, output="sos"),
                   RNG.standard_normal(len(t)))


def env(t, decay, attack=.003):
    return (1 - np.exp(-t / attack)) * np.exp(-t / decay)


def modes(t, frequency, decay=.15, ratios=(1, 1.52, 2.31, 3.87)):
    return sum(np.sin(2 * np.pi * frequency * r * t) * env(t, decay / (1 + i * .55))
               / (1 + i) ** 1.3 for i, r in enumerate(ratios))


def add(dst, at, sample, gain=1):
    start = round(at * RATE)
    end = min(len(dst), start + len(sample))
    if end > start:
        dst[start:end] += gain * sample[:end-start]


def room(x, taps=((.047, .15), (.093, .09), (.161, .04))):
    y = x.copy()
    for delay, gain in taps:
        add(y, delay, x, gain)
    return y


def ui(kind, variant):
    t = clock(.11 if kind in ("hover", "dialogue") else .30)
    f = {"hover": 720, "confirm": 620, "cancel": 460, "dialogue": 420,
         "failure": 230}[kind] * (1 + .07 * variant)
    x = modes(t, f, .028, (1, 2, 3)) * .6 + noise(t, 450, 2400) * env(t, .012) * .3
    if kind in ("confirm", "cancel", "failure"):
        u = clock(.20)
        add(x, .065, modes(u, f * (1.5 if kind == "confirm" else .75), .045, (1, 2, 3)), .65)
    return x


def step(wood, variant):
    t = clock(.34)
    f = (165 if wood else 110) * (1 + .08 * variant)
    x = modes(t, f, .045, (1, 1.71, 2.92)) * .9
    x += noise(t, 120, 1800 if wood else 3300) * env(t, .032) * 1.2
    add(x, .036 + variant * .002, modes(clock(.2), f * 1.3, .027), .25)
    x += noise(t, 200, 1600) * env(t, .075, .025) * (.16 if wood else .45)
    return room(x, ((.021, .08), (.042, .03)))


def pour(variant):
    t = clock(1.65)
    gate = np.minimum(t / .09, 1) * np.clip((1.23 - t) / .18, 0, 1)
    x = noise(t, 280, 3900) * gate * (.26 + .09 * np.sin(t * 39))
    # Overlapping rising bubbles, with a cup resonance under the flow.
    for at in np.arange(.02, 1.22, .043):
        u = clock(.14)
        f = RNG.uniform(400, 1050) * (1 + .1 * variant)
        bubble = np.sin(2 * np.pi * (f * u + 1100 * u*u)) * env(u, .027)
        add(x, at, bubble, RNG.uniform(.04, .14))
    add(x, .01, modes(clock(.6), 340, .13), .14)
    return room(x)


def bell():
    t = clock(1.6)
    x = modes(t, 785, .24, (1, 2.76, 5.4))
    add(x, .17, modes(clock(1.3), 1047, .26, (1, 2.76, 5.4)), .70)
    x += noise(t, 500, 2500) * env(t, .008) * .3
    return room(x)


def order():
    t = clock(.45)
    x = noise(t, 600, 3600) * env(t, .07, .015) * (1 + .5 * np.sin(91 * t))
    add(x, .085, modes(clock(.3), 470, .025, (1, 2, 3)), .14)
    return x


def sealer():
    t = clock(1.65)
    x = modes(t, 140, .04) * .6
    gate = np.clip((t - .08) / .06, 0, 1) * np.clip((1.15 - t) / .12, 0, 1)
    f = 75 * t + 8 * t*t
    motor = sum(np.sin(2 * np.pi * f * k) / k for k in range(1, 9))
    x += (motor * .14 + noise(t, 200, 2500) * .22) * gate
    add(x, 1.14, modes(clock(.45), 215, .035), .7)
    add(x, 1.2, noise(clock(.35), 600, 3400) * env(clock(.35), .055), .2)
    return room(x)


def knock(variant):
    t = clock(1.6)
    x = np.zeros(len(t))
    for at, gain in ((.0, 1), (.23, .8), (.65, 1.05)):
        u = clock(.85)
        hit = modes(u, 100 + variant * 13, .075, (1, 1.58, 2.73, 4.1))
        hit += noise(u, 160, 1900) * env(u, .012) * .6
        add(x, at, hit, gain)
    return room(x, ((.071, .24), (.149, .15), (.281, .07)))


def impact():
    t = clock(1.9)
    x = np.sin(2 * np.pi * (60 * t + 6 * (1 - np.exp(-t * 14)))) * env(t, .18)
    x += noise(t, 100, 2700) * env(t, .11) * .7
    x += modes(t, 191, .24, (1, 1.06, 1.51, 2.07)) * .4
    return room(x, ((.083, .23), (.179, .17), (.337, .10)))


def drip(variant):
    t = clock(1.2)
    x = np.sin(2 * np.pi * (660 * t + (800 + 180 * variant) * t*t)) * env(t, .04)
    x += noise(t, 500, 3100) * env(t, .009) * .35
    return room(x, ((.093, .35), (.231, .21), (.417, .12), (.623, .055)))


def scrape():
    t = clock(1.1)
    x = noise(t, 170, 2200) * env(t, .20, .04) * (1 + .7 * np.sin(t * 157))
    x += modes(t, 91, .12) * .2
    return room(x, ((.08, .2), (.19, .1)))


def goblin(variant):
    t = clock(.95)
    f = 105 + variant * 14 + 22 * np.sin(t * 10) + 13 * np.sin(t * 23)
    phase = np.cumsum(f) / RATE
    # Glottal harmonics weighted by two moving vowel formants; no human recording.
    x = np.zeros(len(t))
    for k in range(1, 30):
        weight = np.exp(-((f*k - 530 - 130*np.sin(t*8)) / 180)**2)
        weight += .45 * np.exp(-((f*k - 1300) / 330)**2)
        x += np.sin(2*np.pi*k*phase) * weight / k
    x += noise(t, 140, 1900) * .06
    x *= env(t, .20, .025) * (.65 + .35 * np.sin(t * 20)**2)
    return room(x)


def ambience(cave):
    # Circular spectral filtering gives genuinely periodic room tone (not a fade gap).
    t = clock(12)
    freq = np.fft.rfftfreq(len(t), 1/RATE)
    white = RNG.standard_normal(len(t))
    spectrum = np.fft.rfft(white)
    shape = (freq / (freq + 90)) ** 2 / (1 + (freq / (900 if cave else 1300)) ** 4)
    x = np.fft.irfft(spectrum * shape, n=len(t))
    x *= .5 + .08 * np.sin(2*np.pi*t/12) + .04 * np.sin(2*np.pi*t/3)
    if cave:
        for at in (1.2, 4.7, 9.1):
            add(x, at, drip(0), .10)
    else:
        x += .025 * np.sin(2*np.pi*100*t) + .01 * np.sin(2*np.pi*200*t)
        for at in (2.1, 7.3):
            add(x, at, modes(clock(.8), 380, .13), .09)
    return x


def master(x, target_db, loop=False):
    # Gentle saturation glues layers, HP removes DC, LP rounds the top end.
    x = np.tanh(x * 1.2)
    if loop:
        f = np.fft.rfftfreq(len(x), 1/RATE)
        x = np.fft.irfft(np.fft.rfft(x) * (f/(f+35))**2 / (1+(f/5500)**8), n=len(x))
    else:
        x = sosfiltfilt(butter(2, [45, 5500], btype="bandpass", fs=RATE, output="sos"), x)
        # Trim only inaudible tail, then short edge fades to suppress discontinuities.
        active = np.flatnonzero(np.abs(x) > np.max(np.abs(x)) * .001)
        x = x[:min(len(x), active[-1] + round(.025*RATE))]
        fade = min(round(.008*RATE), len(x)//4)
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
    active = np.abs(x) > np.max(np.abs(x)) * .04
    rms = np.sqrt(np.mean(x[active]**2))
    x *= 10**(target_db/20) / rms
    true_peak = np.max(np.abs(resample_poly(x, 4, 1)))
    x *= min(1, 10**(-6/20) / true_peak)
    if not loop:
        audible = np.flatnonzero(abs(x) > .0005)
        x = x[:min(len(x), audible[-1] + round(.035*RATE))]
        fade = min(round(.008*RATE), len(x)//4)
        x[-fade:] *= np.linspace(1, 0, fade)
    return np.round(x * 32767).astype('<i2')


def main():
    global RNG
    specs = [
        ("ui.hover", "菜单悬停", 1, lambda v: ui("hover", v)),
        ("ui.confirm", "确认操作", 1, lambda v: ui("confirm", v)),
        ("ui.cancel", "取消操作", 1, lambda v: ui("cancel", v)),
        ("ui.dialogue", "对话文字", 3, lambda v: ui("dialogue", v)),
        ("shop.door_bell", "店门双音铃", 1, lambda v: bell()),
        ("shop.order_open", "展开纸质订单", 1, lambda v: order()),
        ("shop.tea_pour", "倒入奶茶", 2, pour),
        ("shop.sealer", "封口机压合", 1, lambda v: sealer()),
        ("player.step_wood", "木地板脚步", 4, lambda v: step(True, v)),
        ("player.step_stone", "石地脚步", 4, lambda v: step(False, v)),
        ("story.knock", "门后神秘三连敲", 2, knock),
        ("story.impact", "剧情冲击", 1, lambda v: impact()),
        ("ui.failure", "交互失败", 1, lambda v: ui("failure", v)),
        ("ambience.drip", "远处滴水", 2, drip),
        ("ambience.rock_scrape", "岩石摩擦", 1, lambda v: scrape()),
        ("story.goblin", "哥布林含糊嘀咕", 3, goblin),
        ("ambience.shop", "奶茶店室内循环", 1, lambda v: ambience(False)),
        ("ambience.cave", "地下洞穴循环", 1, lambda v: ambience(True)),
    ]
    report, entries, ext = [], [], []
    mapping = ["# 音效 ID 与资源映射（生成文件）", "", "由 `tools/audio/generate_sound_pack.py` 生成。基础 ID 指向首变体；重复播放通过 `choose_variant()` 选择非连续重复的变体 ID。", "", "| 基础 ID | 名称 | 变体 ID / 资源路径 / 秒 |", "| --- | --- | --- |"]
    for index, (sound_id, label, count, synth) in enumerate(specs):
        category, name = sound_id.split(".")
        refs, descriptions = [], []
        looping = sound_id in ("ambience.shop", "ambience.cave")
        target = -32 if looping else (-28 if sound_id == "ui.dialogue" else -23)
        for v in range(count):
            RNG = np.random.default_rng(47001 + index * 100 + v)
            filename = name + (f"_{v+1:02}" if count > 1 else "") + ".wav"
            relative = f"assets/audio/{category}/{filename}"
            path = ROOT / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            pcm = master(synth(v), target, looping)
            with wave.open(str(path), "wb") as wav:
                wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
                wav.writeframes(pcm.tobytes())
            # Explicit PCM import and loop metadata; retain Godot's existing UID.
            import_path = path.with_suffix('.wav.import')
            previous = import_path.read_text(encoding='utf-8') if import_path.exists() else ''
            uid = re.search(r'^uid="[^"]+"', previous, re.M)
            source = 'res://' + relative
            cache = 'res://.godot/imported/' + filename + '-' + hashlib.md5(source.encode()).hexdigest() + '.sample'
            settings = '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n'
            if uid:
                settings += uid[0] + '\n'
            settings += f'path="{cache}"\n\n[deps]\n\nsource_file="{source}"\ndest_files=["{cache}"]\n\n[params]\n\n'
            settings += 'force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\n'
            # Importer enum includes Detect From WAV before Disabled/Forward.
            settings += f'edit/loop_mode={2 if looping else 1}\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n'
            import_path.write_text(settings, encoding='utf-8', newline='\n')
            resource_id = f"s{len(ext)+1}"
            ext.append(f'[ext_resource type="AudioStream" path="res://{relative}" id="{resource_id}"]')
            refs.append(f'ExtResource("{resource_id}")')
            variant_id = sound_id if count == 1 else f"{sound_id}.{v+1:02}"
            descriptions.append(f'`{variant_id}` → `res://{relative}` ({len(pcm)/RATE:.3f})')
            x = pcm.astype(float)/32768
            report.append(dict(id=variant_id, path=relative, loop=looping,
                               seconds=round(len(pcm)/RATE, 6),
                               peak_db=round(20*np.log10(max(abs(x))), 3),
                               sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        entries.append('{"id": "%s", "label": "%s", "loop": %s, "streams": [%s]}' %
                       (sound_id, label, str(looping).lower(), ", ".join(refs)))
        mapping.append(f'| `{sound_id}` | {label} | ' + '<br>'.join(descriptions) + ' |')
    resource = '[gd_resource type="Resource" script_class="SoundLibrary" load_steps=%d format=3]\n\n' % (len(ext)+2)
    resource += '[ext_resource type="Script" path="res://src/resources/audio/sound_library.gd" id="1"]\n'
    resource += '\n'.join(ext) + '\n\n[resource]\nscript = ExtResource("1")\nentries = Array[Dictionary]([\n'
    resource += ',\n'.join(entries) + '\n])\n'
    for relative, content in (
        ('src/resources/audio/sound_library.tres', resource),
        ('assets/audio/manifest.json', json.dumps(report, ensure_ascii=False, indent=2)+'\n'),
        ('docs/sound_library_ids.md', '\n'.join(mapping)+'\n'),
    ):
        path = ROOT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8', newline='\n')
    print(f'Generated {len(report)} WAVs, {len(specs)} base IDs.')


if __name__ == '__main__':
    main()
