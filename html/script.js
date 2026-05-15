const meter = document.getElementById('meter');
const meterStatus = document.getElementById('meterStatus');
const meterFare = document.getElementById('meterFare');
const meterDistance = document.getElementById('meterDistance');
const meterDriveStatus = document.getElementById('meterDriveStatus');
const meterBase = document.getElementById('meterBase');
const meterKmRate = document.getElementById('meterKmRate');
const meterPending = document.getElementById('meterPending');
const meterEstimateRow = document.getElementById('meterEstimateRow');
const meterEstimate = document.getElementById('meterEstimate');

const acceptBox = document.getElementById('acceptBox');
const acceptTitle = document.getElementById('acceptTitle');
const acceptInfo = document.getElementById('acceptInfo');
const acceptHint = document.getElementById('acceptHint');
const acceptKey = document.getElementById('acceptKey');

const rateBox = document.getElementById('rateBox');
const rateTitle = document.getElementById('rateTitle');
const rateSubtitle = document.getElementById('rateSubtitle');
const rateInput = document.getElementById('rateInput');
const rateError = document.getElementById('rateError');
const rateConfirm = document.getElementById('rateConfirm');
const rateCancel = document.getElementById('rateCancel');

const tipBox = document.getElementById('tipBox');
const tipTitle = document.getElementById('tipTitle');
const tipInfo = document.getElementById('tipInfo');
const tipButtons = document.getElementById('tipButtons');
const tipSkip = document.getElementById('tipSkip');

let rateLimits = { min: 5, max: 50, defaultRate: 12 };
let rateErrorTemplate = '';

function postNui(name, data) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    });
}

function formatMoney(value) {
    const num = Number(value) || 0;
    return '$' + num.toFixed(2);
}

function applyRateErrorTemplate(template, min, max) {
    if (!template) {
        return `Enter $${min} – $${max}.`;
    }

    let index = 0;
    const values = [`$${min}`, `$${max}`];

    return template.replace(/%s/g, () => values[index++] || '');
}

function setText(id, text) {
    const el = document.getElementById(id);
    if (el && text) {
        el.textContent = text;
    }
}

function updateEstimate(extra) {
    if (!meterEstimateRow || !meterEstimate) {
        return;
    }

    setText('meterEstimateLabel', extra?.estimateLabel);

    const estimate = Number(extra?.estimatedFinal);
    if (extra?.hasEstimate && !Number.isNaN(estimate) && estimate > 0) {
        meterEstimate.textContent = formatMoney(estimate);
        meterEstimateRow.classList.remove('hidden');
    } else {
        meterEstimateRow.classList.add('hidden');
    }
}

function updateMeter(payload, visible, isDriver, extra) {
    if (!visible) {
        meter.classList.add('hidden');
        return;
    }

    const data = payload || {};
    const info = extra || {};

    meter.classList.remove('hidden');
    meter.classList.toggle('passenger', !isDriver);

    const ui = info;

    setText('meterLabelTaxi', ui.labelTaxi);
    setText('meterLabelDistance', ui.labelDistance);
    setText('meterLabelStatus', ui.labelStatus);
    setText('meterLabelBase', ui.labelBase);
    setText('meterLabelPerKm', ui.labelPerKm);

    const hintEl = document.getElementById('meterHint');
    if (hintEl && ui.meterHint) {
        hintEl.textContent = ui.meterHint;
    }

    if (data.meterStarted) {
        meterStatus.textContent = ui.statusOn || 'ON';
        meterStatus.classList.add('on');
        meterStatus.classList.remove('off');
    } else if (isDriver) {
        meterStatus.textContent = ui.statusReady || 'READY';
        meterStatus.classList.remove('on');
        meterStatus.classList.add('off');
    } else {
        meterStatus.textContent = ui.statusOn || 'ON';
        meterStatus.classList.add('on');
        meterStatus.classList.remove('off');
    }

    meterFare.textContent = formatMoney(data.fare);
    meterDistance.textContent = (Number(data.distanceKm) || 0).toFixed(2) + ' km';
    if (meterDriveStatus) {
        meterDriveStatus.textContent = data.isDriving ? (ui.driving || 'Driving') : (ui.stopped || 'Stopped');
        meterDriveStatus.style.color = data.isDriving ? '#7dffb2' : '#ff9f43';
    }
    meterBase.textContent = formatMoney(data.baseFare);
    meterKmRate.textContent = formatMoney(data.pricePerKm);

    const pending = Number(info.pendingPassengers || data.pendingPassengers || 0) > 0;
    const waiting = info.waitingForPassenger || (!data.meterStarted && isDriver);

    if (meterPending) {
        if (waiting && !pending) {
            meterPending.textContent = ui.pendingWaiting || 'Waiting for passenger';
            meterPending.classList.remove('hidden');
        } else if (pending) {
            meterPending.textContent = ui.pendingAccept || 'Passenger must accept';
            meterPending.classList.remove('hidden');
        } else if (data.meterStarted) {
            meterPending.textContent = ui.tripActive || 'Trip in progress';
            meterPending.classList.remove('hidden');
            meterPending.style.color = '#7dffb2';
        } else {
            meterPending.classList.add('hidden');
        }
    }

    updateEstimate(info);
}

function showAccept(data) {
    acceptTitle.textContent = data.title || 'Taxitarif bestätigen';
    acceptInfo.textContent = data.info || '';
    acceptHint.textContent = data.hint || '';
    acceptKey.textContent = data.acceptKey || 'Y';
    acceptBox.classList.remove('hidden');
}

function hideAccept() {
    acceptBox.classList.add('hidden');
}

function showRateError(msg) {
    if (!msg) {
        rateError.classList.add('hidden');
        rateError.textContent = '';
        return;
    }
    rateError.textContent = msg;
    rateError.classList.remove('hidden');
}

function showRate(data) {
    rateLimits = {
        min: Number(data.min) || 5,
        max: Number(data.max) || 50,
        defaultRate: Number(data.defaultRate) || 12,
    };

    rateTitle.textContent = data.title || 'Preis pro Kilometer';
    rateSubtitle.textContent = data.subtitle || '';
    rateInput.min = rateLimits.min;
    rateInput.max = rateLimits.max;
    rateInput.value = rateLimits.defaultRate;
    rateConfirm.textContent = data.confirmLabel || 'Start';
    rateCancel.textContent = data.cancelLabel || 'Cancel';
    rateErrorTemplate = data.rateErrorTemplate || '';

    showRateError('');
    rateBox.classList.remove('hidden');
    document.body.classList.add('rate-open');

    setTimeout(() => {
        rateInput.focus();
        rateInput.select();
    }, 100);
}

function hideRate() {
    rateBox.classList.add('hidden');
    document.body.classList.remove('rate-open');
    showRateError('');
}

function submitRate() {
    const value = Number(rateInput.value);

    if (!value || value < rateLimits.min || value > rateLimits.max) {
        showRateError(applyRateErrorTemplate(rateErrorTemplate, rateLimits.min, rateLimits.max));
        return;
    }

    postNui('confirmRate', { rate: value });
}

rateConfirm.addEventListener('click', submitRate);

rateCancel.addEventListener('click', () => {
    postNui('cancelRate', {});
});

rateInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
        submitRate();
    } else if (event.key === 'Escape') {
        postNui('cancelRate', {});
    }
});

function showTip(data) {
    if (!tipBox) {
        return;
    }

    tipTitle.textContent = data.title || 'Trinkgeld';
    tipInfo.textContent = data.info || '';
    tipSkip.textContent = data.skipLabel || 'Kein Trinkgeld';
    tipButtons.innerHTML = '';

    const fare = Number(data.fare) || 0;
    const percents = data.percents || [5, 10, 20];

    percents.forEach((percent) => {
        const amount = fare * (percent / 100);
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'tip-btn';
        btn.textContent = '+' + percent + '% (' + formatMoney(amount) + ')';
        btn.addEventListener('click', () => {
            postNui('tipPay', { percent });
        });
        tipButtons.appendChild(btn);
    });

    tipBox.classList.remove('hidden');
    document.body.classList.add('tip-open');
}

function hideTip() {
    if (!tipBox) {
        return;
    }
    tipBox.classList.add('hidden');
    document.body.classList.remove('tip-open');
    tipButtons.innerHTML = '';
}

if (tipSkip) {
    tipSkip.addEventListener('click', () => {
        postNui('tipSkip', {});
    });
}

window.addEventListener('message', (event) => {
    const msg = event.data;

    if (msg.action === 'update') {
        updateMeter(msg.data, msg.visible, msg.driver !== false, msg.extra);
    } else if (msg.action === 'showAccept') {
        showAccept(msg);
    } else if (msg.action === 'hideAccept') {
        hideAccept();
    } else if (msg.action === 'showRate') {
        showRate(msg);
    } else if (msg.action === 'hideRate') {
        hideRate();
    } else if (msg.action === 'showTip') {
        showTip(msg);
    } else if (msg.action === 'hideTip') {
        hideTip();
    }
});
