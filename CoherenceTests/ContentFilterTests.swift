import XCTest
@testable import Coherence

final class ContentFilterTests: XCTestCase {

    func test_ordinaryMeditationTextPasses() {
        for ok in ["Roof before work. Cold enough to see my breath.",
                   "Hard as hell today, damn restless", "Scunthorpe sunrise sit",
                   "assessing my class schedule", "grapefruit and green tea first",
                   "Evening meditation", "I love this", "@jordan.k", "session 5 of 10",
                   "cocktail party later, needed this", "analysis paralysis gone"] {
            XCTAssertEqual(ContentFilter.check(ok), .ok, ok)
        }
    }

    func test_obviousAbuseIsBlocked() {
        for bad in ["fuck you", "you're a bitch", "kys", "send nudes"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_disguisedSpellingsAreBlocked() {
        for bad in ["F.U.C.K", "fvck", "f*ck", "fuuuuck", "b1tch", "f u c k", "k y s", "p0rn"] {
            XCTAssertEqual(ContentFilter.check(bad), .blocked, bad)
        }
    }

    func test_anyBlockedFieldBlocksTheWhole() {
        XCTAssertEqual(ContentFilter.check(["Morning sit", "nice", "porn"]), .blocked)
        XCTAssertEqual(ContentFilter.check(["Morning sit", "", "nice"]), .ok)
    }

    // MARK: Usernames (2026-09-29, guideline 1.2)

    /// A handle is one word, so the whole-word rule could not see inside it:
    /// every one of these passed before the handle check existed.
    func test_handlesHidingAStemAreBlocked() {
        for bad in ["fuckyou", "bigdick", "cuntface", "pornstar", "shithead", "niggerxx",
                    "f_u_c_k", "sh1thead", "d1ck.pic", "hitler88", "kkk_member", "fuuuckyou",
                    "niiiggger", "bullshit", "noshit", "shitass", "b1tchplease", "wh0re",
                    "fuck2you", "f4gg0t", "shite", "nazi_guy"] {
            XCTAssertEqual(ContentFilter.checkHandle(bad), .blocked, bad)
        }
    }

    /// The whole-word rule still runs on a handle, so a listed word alone is
    /// caught even where no stem covers it.
    func test_handlesThatAreAListedWordAreBlocked() {
        for bad in ["twat", "b1tch", "@porn"] {
            XCTAssertEqual(ContentFilter.checkHandle(bad), .blocked, bad)
        }
    }

    /// Handles that would read as 808, Otto or their staff are never handed
    /// out, alone or combined only with each other or a number.
    func test_reservedHandles() {
        for handle in ["808", "meditate808", "otto", "support", "admin", "administrator", "apple",
                       "app", "official", "staff", "team", "moderator", "mod", "help", "security",
                       "root", "system", "lockout", "otto_808", "808.support", "admin42",
                       "apple_support", "meditate_808", "otto.official", "808team", "@Otto"] {
            XCTAssertEqual(ContentFilter.checkHandle(handle), .reserved, handle)
        }
    }

    /// Real words and names that contain a stem or a reserved word pass, and
    /// so do the "name.808" suggestions the claim screen makes itself.
    func test_innocentHandlesPass() {
        for ok in ["grape", "scunthorpe_fan", "peacock", "dickens", "cocktail", "therapist",
                   "hancock", "hitchcock", "cockatoo", "dickinson", "yamashita", "yoshito",
                   "ishita", "kshitij", "shiite", "shiitake", "nazia", "ashkenazi", "pornsak",
                   "niggle", "saltwater", "sweetwater", "poorness", "analyst", "document",
                   "cumberland", "night.owl", "melvin808", "melvin.808", "melvin_808",
                   "the808", "otto_k", "mod_squad", "root_beer", "happy", "teamwork",
                   "appleseed", "aziz", "jordan.k", "sam_p"] {
            XCTAssertEqual(ContentFilter.checkHandle(ok), .ok, ok)
        }
    }

    // MARK: Names (2026-09-29, second pass)

    /// Real first and last names from many places, and the ones a reviewer
    /// found the first handle check refusing (Thai names ending in -porn,
    /// Yoshiteru, Riddick, Glasscock, Slutsky, Fagg, Shittu, Alanazi, and
    /// "crush_it" read across its underscore). None may be blocked. "otto"
    /// is a German first name and reads as reserved, which is not blocked.
    func test_namesAreNeverBlocked() {
        let corpus = """
        siriporn kanokporn jiraporn supaporn duangporn thanaporn porntip pornpun somporn pornchai
        pornsak pornthip pornpimol poornima poorna sampoorna alanazi al_anazi anazi nazik nazila
        nazionale nazia nazir nazim ashkenazi shital shitala shitara shittu shitole shitaye
        shitanshu shitij mashiter ashitey kshitij kshitiz yoshiteru toshiteru yoshitsune yoshitsugu
        ishitsuka yamashita kinoshita morishita matsushita takeshita yoshito ishita ashita harshit
        harshita akshit akshita rakshit darshit dikshit nishith shiting shitong shitao shitian
        shitou riddick reddick braddick maddick dickman dickmann dickel dickert dickstein dicko
        dickens dickinson dickson dickerson glasscock pidcock moorcock leacock wilcock hiscock
        haycock heathcock hedgecock allcock handcock meacock cockrell cockrum cockayne cocking
        cockcroft shinnecock hancock babcock hitchcock peacock woodcock alcock adcock laycock pocock
        slutsky slutskaya sluter fagg faggin faggiano faggioli crush_it push_it cash_it finish_it
        james john robert michael william david richard joseph thomas charles christopher daniel
        matthew anthony mark donald steven paul andrew joshua kenneth kevin brian george timothy
        ronald edward jason jeffrey ryan jacob gary nicholas eric jonathan stephen larry justin
        scott brandon benjamin samuel gregory alexander frank patrick raymond jack dennis jerry
        tyler aaron jose adam nathan henry douglas zachary peter kyle noah ethan jeremy walter
        christian keith roger terry austin sean gerald carl harold dylan arthur lawrence jordan
        jesse bryan billy bruce gabriel joe logan alan juan albert willie elijah wayne randy vincent
        mason roy ralph bobby russell bradley philip eugene mary patricia jennifer linda elizabeth
        barbara susan jessica sarah karen lisa nancy betty margaret sandra ashley kimberly emily
        donna michelle carol amanda dorothy melissa deborah stephanie rebecca sharon laura cynthia
        kathleen amy angela shirley anna brenda pamela emma nicole helen samantha katherine
        christine debra rachel carolyn janet catherine maria heather diane ruth julie olivia joyce
        virginia victoria kelly lauren christina joan evelyn judith megan andrea cheryl hannah
        jacqueline martha gloria teresa ann sara madison frances kathryn janice jean abigail alice
        judy sophia grace denise amber doris marilyn danielle beverly isabella theresa diana natalie
        brittany charlotte marie kayla alexis lori smith johnson williams brown jones garcia miller
        davis rodriguez martinez hernandez lopez gonzalez wilson anderson taylor moore jackson
        martin lee perez thompson white harris sanchez clark ramirez lewis robinson walker young
        allen king wright torres nguyen hill flores green adams nelson baker hall rivera campbell
        mitchell carter roberts gomez phillips evans turner diaz parker cruz edwards collins reyes
        stewart morris morales murphy cook rogers gutierrez ortiz morgan cooper peterson bailey reed
        howard ramos kim cox ward richardson watson brooks chavez wood bennett gray mendoza ruiz
        hughes price alvarez castillo sanders patel myers long ross foster jimenez cockburn cummings
        cumming aarav vivaan aditya vihaan arjun sai reyansh ayaan krishna ishaan shaurya atharv
        advik pranav advait dhruv kabir ritvik aarush kayaan darsh veer aanya diya ananya pari
        aadhya saanvi myra anika navya riya priya pooja sneha deepika kavya lakshmi shruti neha
        swati sunita anita kavita ashish ashok ashutosh shivam shiv rakesh suresh ramesh mahesh
        dinesh ganesh rajesh mukesh nitin amit sumit rohit mohit lalit rishabh shikha shilpa shweta
        nishant nishita mishti hiroshi takeshi satoshi yoshi kenji haruto yuto sota yamato riku
        akira daiki kaito hinata sakura yui aoi rin mio yuna akari mei hana saki yoshida kishida
        nishida tanaka suzuki takahashi watanabe ito nakamura kobayashi kato yoshimura fukuda
        fukushima fukui ishikawa hashimoto shimizu yamaguchi matsumoto inoue kimura hayashi saito
        yamamoto sasaki yamada mori abe ikeda ishii ogawa okada goto hasegawa murakami kondo
        sakamoto endo aoki fujii nishimura ota miura fujita okamoto matsuda nakagawa nakano harada
        ono tamura takeuchi kaneko wada nakayama ishihara shibata sakai kudo yokoyama miyazaki
        miyamoto uchida takagi ando taniguchi maruyama imai takada fujimoto takeda murata ueno
        sugiyama masuda sugawara hirano otsuka chiba kubo matsui iwasaki sakurai noguchi matsuo
        nomura kikuchi sano onishi sugimoto arai hamada ichikawa furukawa mizuno komatsu shimada
        igarashi takano yamanaka kojima tsuji tsuchiya kitamura hori yoshitaka oshitari hoshitani
        somchai somsak wichai kittisak nattapong suriya pim ploy wei fang li wang zhang liu chen
        yang huang zhao wu zhou xu sun ma zhu hu guo he gao lin luo zheng liang xie song tang han
        feng deng cao peng zeng xiao tian dong pan yuan cai jiang yu du ye cheng su lu ding ren shen
        yao cui zhong tan fan jin shi liao jia xia fu bai zou meng xiong qin qiu yin xue yan duan
        lei hou long tao gu mao hao gong shao wan qian dai hong jun ming hui ling xiu ying jing
        qiang jie yong chao bo ning xin yi zihan haoran yuxuan zixuan yichen minjun seojun doyun
        jiho jiwoo seoyeon hayoon minseo seoah park choi jung kang cho yoon jang lim oh seo shin
        kwon hwang ahn jeon mohammed muhammad ahmed ali omar hassan hussein ibrahim youssef khalid
        abdullah mahmoud mustafa said tariq karim nasser faisal hamza bilal fatima aisha maryam
        zainab layla noor huda amina rania salma yasmin nour alotaibi alharbi alghamdi alzahrani
        alshehri alqahtani aldosari almutairi alshammari nazih luis carlos jorge pedro miguel
        alejandro diego javier francisco antonio manuel rafael fernando pablo sergio andres ricardo
        eduardo lucia sofia valentina camila martina daniela gabriela paula carmen ana marta
        fernandez moreno romero alonso navarro dominguez vazquez gil serrano blanco suarez molina
        ortega delgado castro rubio marin sanz nunez iglesias medina garrido cortes santos lozano
        guerrero cano prieto mendez calvo gallego vidal leon marquez herrera pena cabrera campos
        vega fuentes carrasco diez caballero nieto aguilar pascual santana herrero lorenzo montero
        hidalgo gimenez ibanez ferrer duran santiago benitez mora vicente vargas arias carmona
        crespo roman pastor soto saez velasco moya soler parra esteban bravo gallardo rojas silva
        oliveira souza rodrigues ferreira alves pereira lima gomes costa ribeiro martins carvalho
        almeida lopes sousa fernandes vieira barbosa rocha dias nascimento andrade moreira nunes
        marques machado mendes freitas cardoso goncalves teixeira rossi russo ferrari esposito
        bianchi romano colombo ricci marino greco bruno gallo conti deluca mancini giordano rizzo
        lombardi moretti barbieri fontana santoro mariani rinaldi caruso ferrara galli martini leone
        longo gentile martinelli vitale lombardo serra coppola desantis marchetti parisi villa conte
        ferraro ferri fabbri bianco marini grasso valentini messina sala gatti pellegrini palumbo
        farina rizzi monti cattaneo morelli amato silvestri mazza testa grassi carbone giuliani
        benedetti barone caputo guerra palmieri bernardi fiore bellini basile riva donati vitali
        battaglia sartori neri milani pagano orlando negri muller schmidt schneider fischer weber
        meyer wagner becker schulz hoffmann schafer koch bauer richter klein wolf schroder neumann
        schwarz zimmermann braun kruger hofmann hartmann lange schmitt werner schmitz krause meier
        lehmann schmid schulze maier kohler herrmann konig walter mayer huber kaiser fuchs peters
        lang scholz moller weiss hahn schubert vogel friedrich keller gunther berger winkler roth
        beck lorenz baumann franke albrecht schuster simon ludwig bohm winter kraus schumacher
        kramer vogt stein jager sommer gross seidel heinrich brandt haas schreiber graf schulte
        dietrich ziegler kuhn pohl engel horn busch bergmann voigt sauer arnold wolff pfeiffer fick
        niggli bernard dubois petit durand leroy moreau laurent lefebvre michel bertrand roux
        fournier morel girard andre lefevre mercier dupont lambert bonnet francois legrand garnier
        faure rousseau blanc guerin roussel nicolas perrin morin mathieu clement gauthier dumont
        fontaine chevalier robin ivanov smirnov kuznetsov popov vasiliev petrov sokolov mikhailov
        novikov fedorov morozov volkov alekseev lebedev semenov egorov pavlov kozlov stepanov
        nikolaev orlov andreev makarov nikitin zakharov kowalski nowak wisniewski wojcik kowalczyk
        kaminski lewandowski zielinski szymanski wozniak dabrowski kozlowski jankowski mazur
        kwiatkowski krawczyk piotrowski grabowski adebayo oluwaseun chinedu emeka ngozi chioma kwame
        kofi ama akua yaw abena tendai tatenda thabo sipho nomvula lerato themba zanele bongani
        diallo traore keita coulibaly toure sow ba ndiaye diop fall sy mensah owusu boateng asante
        okafor okonkwo obi eze nwosu adeyemi ogunleye balogun bello abubakar musa yusuf kamau
        wanjiku otieno achieng mwangi njoroge kipchoge tesfaye alemayehu haile tadesse girma bekele
        abebe tran le pham hoang huynh phan vu vo dang bui do ho ngo duong ly phuc phuong thanh minh
        anh linh trang thu hoa lan mai tuan dung hung quang hieu khanh duc dekock vandyke appleby
        staffan ottoman scunthorpe_fan cockatoo shiitake shiite therapist niggle saltwater
        sweetwater poorness analyst document cumberland night.owl melvin808 melvin.808 the808 otto_k
        mod_squad root_beer teamwork appleseed happy dani1990 jenni99 rani99 mini99 jenni1996 sam_p
        jordan.k
        """
        let names = corpus.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        XCTAssertGreaterThan(names.count, 1000)
        for name in names {
            XCTAssertNotEqual(ContentFilter.checkHandle(name), .blocked, name)
        }
    }

    /// The spellings a reviewer used to get past the first handle check.
    func test_disguisedHandlesAreBlocked() {
        for bad in ["fvckyou", "fvckoff", "ni99er", "ni66er", "niqqa", "nlgger", "fagot", "phuck",
                    "fuk", "b1atch", "sh_it", "fu.ck", "fa66ot", "nigg"] {
            XCTAssertEqual(ContentFilter.checkHandle(bad), .blocked, bad)
        }
    }

    /// Reserved words glued together, or spelled with look-alike digits.
    func test_gluedAndLookalikeReservedHandles() {
        for handle in ["applesupport", "ottosupport", "ottoofficial", "adminteam", "supportteam",
                       "808helpdesk", "helpdesk", "supp0rt", "adm1n", "0tto"] {
            XCTAssertEqual(ContentFilter.checkHandle(handle), .reserved, handle)
        }
    }

    /// A separator is a word boundary: "crush_it" is two words, not "shit".
    /// And a year or a number at the end is never read as letters.
    func test_boundariesAndNumbersDoNotManufactureAStem() {
        for ok in ["crush_it", "push_it", "cash_it", "finish_it", "dani1990", "jenni99", "rani99",
                   "mini99", "jenni1996"] {
            XCTAssertEqual(ContentFilter.checkHandle(ok), .ok, ok)
        }
    }

    /// Free text keeps the whole-word rule: a caption is not a handle.
    func test_freeTextIsStillWholeWord() {
        XCTAssertEqual(ContentFilter.check("Scunthorpe sunrise, then a cocktail"), .ok)
        XCTAssertEqual(ContentFilter.check("analysis before the session"), .ok)
    }
}
