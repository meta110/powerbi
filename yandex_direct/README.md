# Выгрузка статистики Яндекс Директ

Инструкция для функции https://github.com/meta110/pq_ya_direct/blob/master/direct_stat.m

Предназначена для выгрузки статистики рекламных кампаний за выбранный промежуток времени по нужному списку показателей напрямую в Power BI или Excel.

Функция работает с сервисом Reports API Яндекс Директ 5 версии: https://yandex.ru/dev/direct/doc/reports/reports-docpage/
## Инструкция по работе
1. Для начала залогиньтесь в нужном аккаунте Яндекс и получите токен авторизации по ссылке: https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d
1. Согласитесь предоставить доступ к аккаунту (кроме вас им никто не сможет воспользоваться, если, конечно, вы не отдадите кому-то свой токен). Дополнительная информация: https://yandex.ru/dev/direct/doc/start/token-docpage/
1. Скопируйте токен
1. Создайте новый пустой запрос в Power Query для Power Bi или Excel и вставьте в него исходный код функции https://raw.githubusercontent.com/meta110/pq_ya_direct/master/direct_stat.m
1. Вставьте токен в поле функции "Авторизационный токен" и заполните остальные параметры функции на свой вкус.
1. Выполните функцию. Отчет подготавливается в режиме оффлайн, поэтому через некоторое время обновляйте запрос пока не получите таблицу с данными. Если заново запросить подготовленный отчёт с теми же параметрами, то он загрузится незамедлительно.

## Описание параметров
Все параметры необязательные, но без токена ничего не выйдет.

Параметр|Тип|Значение по умолчанию|Описание
--------|---|---------------------|---
Дата начала интервала|date|сегодня|Дата начала отчета не позднее сегодняшней
Дата окончания интервала|date|30 дней назад|Дата окончания отчета не позднее даты начала
Поля отчета в списке или строкой через запятую|any|выбранные в коде функции|Поля можно передать в виде списка или срокой с любым их разделителей "#(tab) ,;". Выбирайте поля из отчета CUSTOM_REPORTS https://yandex.ru/dev/direct/doc/reports/fields-list-docpage/
Название отчета|text|пусто|Если во время экспериментов API будет "ругаться", что такой отчёт с другими параметрами уже есть, просто придумайте уникальное название :smirk:
Логин аккаунта клиента|text|пусто|Если вы работаете в агентском аккаунте, то для получения статистики клиента укажите его логин (тот, что из почты до @)
Авторизационный токен|text|пусто|Для начала работы залогиньтесь в нужном аккаунте Яндекс и получите токен авторизации по ссылке: https://oauth.yandex.ru/authorize?response_type=token&client_id=764f4af41256427ba87965a7ed31ea3d

## Повышение собственной производительности
Несколько советов, помогающих упростить вашу работу:
* Чтобы задать список полей, используемых по-умолчанию, закомментируйте ненужные поля с помощью "//" и снимите комментарии напротив нужных полей. Список полей присваивается переменной fields в строках кода с 25 по 88.
* Чтобы постоянно не указывать токен авторизации, создайте параметр и запишите в него токен. Токен хранится в переменной tokenYandexMetrika: закомментируйте строку 19, укажите название параметра в строке 20 и снимите с нее комментарий.
* Диапазон дат по-умолчанию задается в переменных endDate и beginDate в строках 94 и 95.

## Вопросы
С вопросами и предложениями стучитесь:
* в фейсбук https://www.facebook.com/iliah.nazarov
* в телеграм https://t.me/IlyaNazarov