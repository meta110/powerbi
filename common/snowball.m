// стеммер http://snowball.tartarus.org/algorithms/russian/stemmer.html
// прошел тест https://github.com/mazko/jssnowball/tree/master/js_snowball/tests/js
// в метаданных возвращает найденную часть речи
(word as text) => // если слово состоит из символов, отличных от а-я, то оно вернется в неизменном виде
let
    //word = "уставший",

    letters = {"а".."я"},

    matches = ( word, endings ) => let
        porter = Record.Field( PORTER, endings ), // получаю нужный список суффиксов и окончаний
        has_groups = Value.Is( porter, type list ), // проверяю группы в списке
        l = 
            if has_groups then // если есть группы, то 
                List.Combine(List.Transform(Text.Split(porter{0},","), each {"а" & _, "я" & _})) // комбинирую первую с "а" и "я"
                & Text.Split(porter{1},",") // вторую просто разрезаю по запятым
            else Text.Split(porter,","), // просто нарезаю по запятым
        s = List.Sort( l, (x, y) => Value.Compare( Text.Length( y ), Text.Length( x ))), // сортирую в порядке убывания длины. Возможно, есть смысл заранее это сделать, но сейчас не хочется )
        m = List.Transform( s, each Text.EndsWith( word, _ )), // проверяю каждое окончание, по идее можно было бы прерваться после первого совпадения. Вероятно, без генератора списка не обойтись
        pretend = s{List.PositionOf( m, true )}, // кандидат на выбывание (самое длинное найденное совпадение)
        start = Text.Start( pretend, 1 ), // первая буква в этом слове
        f = if has_groups and pretend <> "ят" and ( start = "а" or start = "я" ) then // если список комбинировал
                Text.TrimStart( pretend, start ) // то отрезаю первую букву "а" или "я", за исключением окончания "ят"
            else pretend, 
        r = Text.Start( word, Text.Length( word ) - Text.Length( f ) ), // вырезаю начало слова
        return = 
            if List.AnyTrue( m ) then r meta [ part = endings ] // были совпадения - возвращаю результат
            else word meta [ part = null ] // не было совпадений - возвращаю исходное слово
    in return,
    

    vovels = Text.ToList( PORTER[VOVEL] ), // список гласных
    first_vovel = Text.PositionOfAny( Source, vovels ), // положение первой гласной
    RV = Text.Range( Source, first_vovel + 1 ), // регион RV

    R2 = (RV) => let // второй регион http://snowball.tartarus.org/texts/r1r2.html
        RV_map = Text.Combine( // карта гласных и согласных букв в окончании
            List.Transform( 
                Text.ToList(RV), 
                each if List.Contains( vovels, _) then "a" // гласные будут "а"
                    else "b" // согласные будут "b"
            )
        ) 
    in Text.Range( 
        RV, 
        try Text.PositionOf( RV_map, "ba", 2 ){1} + 1 // позиция второго перехода согласная-гласная
            otherwise Text.Length( RV ) // режу под корень
    ),
    
    Source = Text.Replace(Text.Lower(word), "ё", "е"), // на всякий случай заменяю все "ё" на "е"

    PORTER = [
        VOVEL = "аеиоуыэюя", // список гласных
        PERFECTIVEGERUND = {
            "в,вши,вшись", // должны следовать за "а" или "я"
            "ив,ивши,ившись,ыв,ывши,ывшись"
        },
        ADJECTIVE = "ее,ие,ые,ое,ими,ыми,ей,ий,ый,ой,ем,им,ым,ом,его,ого,ему,ому,их,ых,ую,юю,ая,яя,ою,ею", // прилагательное
        PARTICIPLE = { // причастие?
            "ем,нн,вш,ющ,щ", // должны следовать за "а" или "я"
            "ивш,ывш,ующ"
        }, 
        REFLEXIVE = "ся,сь", // возвратный глагол 
        VERB = { // глагол
            "ла,на,ете,йте,ли,й,л,ем,н,ло,но,ет,ют,ны,ть,ешь,нно", // должны следовать за "а" или "я"
            "ила,ыла,ена,ейте,уйте,ите,или,ыли,ей,уй,ил,ыл,им,ым,ен,ило,ыло,ено,ят,ует,уют,ит,ыт,ены,ить,ыть,ишь,ую,ю"}, 
        NOUN = "а,ев,ов,ие,ье,е,иями,ями,ами,еи,ии,и,ией,ей,ой,ий,й,иям,ям,ием,ем,ам,ом,о,у,ах,иях,ях,ы,ь,ию,ью,ю,ия,ья,я", // существительное
        SUPERLATIVE = "ейш,ейше", // превосходная степень?
        DERIVATIONAL = "ост,ость" // существительное образовано от другой части речи
    ],

    step1 = matches( RV, "PERFECTIVEGERUND" ),
    m1 = Value.Metadata( return ), // как-нибудь прокину метаданные с предполагаемой частью речи до результата
    step1a = matches( RV,"REFLEXIVE" ),

    step1b1 = matches( step1a,"ADJECTIVE" ),
    step1b2 = 
        if step1b1 <> step1a then matches( step1b1, "PARTICIPLE" ) meta [part = "ADJECTIVAL" ] // нужно ли менять часть речи?
        else step1a,
    step1c = matches( step1a, "VERB" ),
    step1d = matches( step1a, "NOUN" ),
    
    step1result =
        if step1 <> RV then step1
        else List.First(
            List.Sort(
                {step1b2, step1c, step1d}, 
                (x, y) => Value.Compare(Text.Length(x), Text.Length(y)) // сортирую по возрастанию длины в буквах
            )
        ),
        
    step2 = Text.TrimEnd( step1result, "и" ) meta [ part = Value.Metadata(step1result)[part] ], // сохраняю метаданные

    step2R2 = R2( step2 ), // спорное решение искать R2 на этом шаге, но оно не противоречит алгоритму
    step3 = 
        if matches( step2R2, "DERIVATIONAL" ) <> step2R2 then // если нашел совпадение в R2
            matches( step2, "DERIVATIONAL" ) // удаляю его из RV
        else step2, // оставляю как есть

    step4super = matches( step3, "SUPERLATIVE" ), // буду проверять совпадение дальше
    step4 = 
        if Text.EndsWith( step3, "ь" ) or Text.EndsWith( step3, "нн" ) then // если оканчивается на "нн" или "ь"
            Text.Start( step3, Text.Length( step3 ) - 1 ) meta [ part = Value.Metadata(step3)[part] ] // удаляю последнюю букву
        else if step4super <> step3 then // был найден SUPERLATIVE
            if Text.EndsWith( step4super, "нн" ) then // проверяю на двойную "н"
                Text.Start( step4super, Text.Length( step4super ) - 1 ) meta [ part = Value.Metadata(step4super)[part] ]// удаляю одну "н" из "нн"
                else step4super 
        else step3,

    return = 
        if List.ContainsAll( letters, Text.ToList( Source ) ) // только буквы кириллицы
            and first_vovel >= 0 // есть хотя бы 1 гласная
        then ( Text.Start(Source, first_vovel+1) & step4 ) meta [ part = Value.Metadata(step4)[part] ]// запускаю преобразование
        else word meta [ part = "UNKNOWN" ]// возвращаю исходное слово
in
    return
