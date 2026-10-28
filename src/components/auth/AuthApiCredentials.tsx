import { memo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { checkApiCredentials, getAreApiCredentialsRejected, storeApiCredentials } from '../../util/apiCredentials';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import InputText from '../ui/InputText';
import Link from '../ui/Link';

const API_DEVELOPMENT_URL = 'https://my.telegram.org/apps';

const AuthApiCredentials = () => {
  const { initApi, openUrl } = getActions();

  const lang = useLang();

  const [apiId, setApiId] = useState('');
  const [apiHash, setApiHash] = useState('');
  const [hasError, setHasError] = useState(getAreApiCredentialsRejected);

  const handleApiIdChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setApiId(e.target.value.trim());
    setHasError(false);
  });

  const handleApiHashChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setApiHash(e.target.value.trim());
    setHasError(false);
  });

  const handleOpenApiDevelopment = useLastCallback(() => {
    openUrl({ url: API_DEVELOPMENT_URL, shouldSkipModal: true });
  });

  const handleSubmit = useLastCallback((e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    const parsedApiId = Number(apiId);
    if (!checkApiCredentials(parsedApiId, apiHash)) {
      setHasError(true);
      return;
    }

    storeApiCredentials({ apiId: parsedApiId, apiHash });
    initApi();
  });

  return (
    <div id="auth-api-credentials-form" className="custom-scroll">
      <div className="auth-form">
        <div id="logo" />
        <h1>Liquidgram</h1>
        <p className="note">{lang('LiquidApiDescription')}</p>
        <form className="form" action="" onSubmit={handleSubmit}>
          <InputText
            id="liquid-api-id"
            label={lang('LiquidApiId')}
            value={apiId}
            inputMode="numeric"
            autoComplete="off"
            error={hasError ? lang('LiquidApiInvalid') : undefined}
            onChange={handleApiIdChange}
          />
          <InputText
            id="liquid-api-hash"
            label={lang('LiquidApiHash')}
            value={apiHash}
            autoComplete="off"
            onChange={handleApiHashChange}
          />
          <Button className="auth-button" type="submit" ripple disabled={!apiId || !apiHash}>
            {lang('LiquidApiContinue')}
          </Button>
        </form>
        <p className="note">
          <Link isPrimary onClick={handleOpenApiDevelopment}>{lang('LiquidApiGetKeys')}</Link>
        </p>
      </div>
    </div>
  );
};

export default memo(AuthApiCredentials);
